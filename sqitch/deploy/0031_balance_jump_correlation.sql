-- Deploy supabase:0031_balance_jump_correlation to pg
-- Diagnostic tooling for investigating unexpected prepay balance jumps.
--
-- 1. Name meter event type 48.
--
-- Type 48 is not defined in the Emlite protocol enum
-- (emop-frame-protocol/formats/emop_event_log_response.ksy has a gap at
-- 45-60) and had no row in flows.meter_event_log_type, so it was showing up
-- unnamed and was easy to overlook.
--
-- Empirically it is the meter's "credit token accepted / topup applied"
-- event. Across the whole MGF database 1161 of 1295 type-48 rows occur within
-- +/-10 minutes of a myenergy.topups.used_at, and the match holds for every
-- topup source (payment, gift, solar_credit, adjustment). Worked examples on
-- HMCE Plot-21 (23 Jul 2026) and HMCE Plot-43 (23 Jul, 29 Aug 2026) all line
-- up within a few seconds.
--
-- The name below is inferred from that correlation, not from the spec. If the
-- team prefers platform terminology, TOPUP_APPLIED is an acceptable
-- alternative (the underlying behaviour is a credit application regardless of
-- source).
--
-- 2. myenergy.uncorrelated_balance_jumps() - diagnostic function.
--
-- Lists jumps in flows.meter_prepay_balance and flags whether each is
-- correlated with a topup, i.e. either:
--   * a flows.meter_event_log row with event_type = 48 (CREDIT_TOKEN_APPLIED)
--     within event_window_minutes of the jump, or
--   * a myenergy.topups row (used_at) for the same meter within
--     topup_window_minutes of the jump.
--
-- The two windows are deliberately independent. Event 48 lands within seconds
-- of a topup used_at, so it should be tight (default +/-1h) or it
-- mis-attributes a jump to an unrelated token push up to half a day later.
-- The topups row, on the other hand, may be created well before the token is
-- pushed, so a broad default (+/-12h) is appropriate.
--
-- A jump correlated with neither is suspicious - most likely an untracked
-- emergency-credit grant / debt-recovery adjustment, which the meter does not
-- appear to log as an event.
--
-- The function reports the two flags plus:
--   * direction       - 'credit' (balance up) or 'debit' (balance down)
--   * likely_ec_grant - balance_after landed within ec_tolerance of the
--                       meter's active_emergency_credit
--   * correlation     - correlated / missing_event_48 / missing_topup / missing_both
--
-- Filtering notes (from a 90-day MGF sweep):
--   * Every uncorrelated jump below GBP10 was DOWNWARD (debt recovery /
--     standing-charge / batch tariff corrections). credit_only := true is the
--     single most effective filter - it collapses ~385 missing_both rows to a
--     handful.
--   * Raising min_abs_diff also removes most of the noise.
--   * likely_ec_grant identifies the "balance reset to ~GBP15" signature.
--
-- With the default only_uncorrelated := true only jumps that are missing at
-- least one signal are returned; pass false to see every jump with its flags.
--
-- NOTE: flows.meter_prepay_balance is a Timescale hypertable. On MGF always
-- pass a meter and/or a time range.
--
-- 3. myenergy.untracked_prepay_credits() - alert-facing wrapper.
--
-- Returns only "untracked credits": upward balance jumps that have NO
-- myenergy.topups record and are NOT an emergency-credit grant. These are the
-- rows that should not exist - a credit landed on the meter without the
-- platform recording a topup for it.
--
-- Note this keeps rows that DO have a type-48 event but no topup
-- (correlation = 'missing_topup'): the meter saw a credit token the platform
-- has no topup for, which is exactly the suspicious case. It drops
-- 'missing_event_48' rows because those have a recorded topup and are
-- therefore tracked (that class is a sync-health signal, alerted separately).
--
-- Defaults are shaped for a Grafana alert rule that evaluates a disjoint,
-- mature slice so each jump is assessed exactly once:
--     since = now() - 3h, until = now() - 1h, maturity = 1h
-- i.e. "the 3h-to-1h-ago bucket". Every jump falls in exactly one evaluation
-- window and cannot re-fire. The underlying function is called with a
-- one-hour-wider from_ts so lag() has context for a jump that sits exactly on
-- the `since` boundary.
--
-- See workspace-simt/prepay-untracked-credits-grafana-alert.yaml for the draft
-- rule and workspace-simt/prepay-untracked-credits-dashboard.md for dashboards.

BEGIN;

INSERT INTO flows.meter_event_log_type (id, name) VALUES
    (48, 'CREDIT_TOKEN_APPLIED')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION myenergy.uncorrelated_balance_jumps(
    meter_id_in          uuid        DEFAULT NULL,
    from_ts              timestamptz DEFAULT NULL,
    to_ts                timestamptz DEFAULT NULL,
    min_abs_diff         numeric     DEFAULT 1.0,
    credits_only         boolean     DEFAULT false,
    event_window_minutes integer     DEFAULT 60,
    topup_window_minutes integer     DEFAULT 720,
    only_uncorrelated    boolean     DEFAULT true,
    ec_tolerance         numeric     DEFAULT 0.5
)
RETURNS TABLE (
    meter_id       uuid,
    serial         text,
    meter_name     text,
    jump_at        timestamptz,
    direction      text,
    balance_before numeric,
    balance_after  numeric,
    jump_amount    numeric,
    has_event_48   boolean,
    has_topup      boolean,
    likely_ec_grant boolean,
    correlation    text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
WITH readings AS (
    SELECT b.meter_id,
           b.timestamp,
           b.balance,
           lag(b.balance) OVER (
               PARTITION BY b.meter_id ORDER BY b.timestamp
           ) AS prev_balance
    FROM flows.meter_prepay_balance b
    WHERE (meter_id_in IS NULL OR b.meter_id = meter_id_in)
      AND (from_ts IS NULL OR b.timestamp >= from_ts)
      AND (to_ts   IS NULL OR b.timestamp <= to_ts)
),
jumps AS (
    SELECT r.meter_id,
           r.timestamp                 AS jump_at,
           r.prev_balance              AS balance_before,
           r.balance                   AS balance_after,
           r.balance - r.prev_balance  AS jump_amount
    FROM readings r
    WHERE r.prev_balance IS NOT NULL
      AND abs(r.balance - r.prev_balance) >= min_abs_diff
      AND (NOT credits_only OR r.balance > r.prev_balance)
),
flagged AS (
    SELECT j.meter_id,
           reg.serial,
           reg.name AS meter_name,
           j.jump_at,
           j.balance_before,
           j.balance_after,
           j.jump_amount,
           EXISTS (
               SELECT 1
               FROM flows.meter_event_log e
               WHERE e.meter_id = j.meter_id
                 AND e.event_type = 48
                 AND e.timestamp BETWEEN j.jump_at - make_interval(mins => event_window_minutes)
                                     AND j.jump_at + make_interval(mins => event_window_minutes)
           ) AS has_event_48,
           EXISTS (
               SELECT 1
               FROM myenergy.topups t
               JOIN myenergy.meters m ON m.id = t.meter
               WHERE m.serial = reg.serial
                 AND t.used_at BETWEEN j.jump_at - make_interval(mins => topup_window_minutes)
                                   AND j.jump_at + make_interval(mins => topup_window_minutes)
           ) AS has_topup,
           EXISTS (
               SELECT 1
               FROM flows.meter_shadows_tariffs tariff
               WHERE tariff.serial = reg.serial
                 AND tariff.active_emergency_credit IS NOT NULL
                 AND abs(j.balance_after - tariff.active_emergency_credit) <= ec_tolerance
           ) AS likely_ec_grant
    FROM jumps j
    JOIN flows.meter_registry reg ON reg.id = j.meter_id
)
SELECT f.meter_id,
       f.serial,
       f.meter_name,
       f.jump_at,
       CASE WHEN f.jump_amount > 0 THEN 'credit' ELSE 'debit' END AS direction,
       f.balance_before,
       f.balance_after,
       f.jump_amount,
       f.has_event_48,
       f.has_topup,
       f.likely_ec_grant,
       CASE
           WHEN f.has_event_48 AND f.has_topup         THEN 'correlated'
           WHEN NOT f.has_event_48 AND NOT f.has_topup THEN 'missing_both'
           WHEN NOT f.has_event_48                     THEN 'missing_event_48'
           ELSE 'missing_topup'
       END AS correlation
FROM flagged f
WHERE NOT only_uncorrelated
   OR NOT (f.has_event_48 AND f.has_topup)
ORDER BY f.jump_at DESC;
$$;

ALTER FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, boolean, integer, integer, boolean, numeric)
    OWNER TO :"adminrole";

COMMENT ON FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, boolean, integer, integer, boolean, numeric)
    IS 'List prepay balance jumps with flags for correlation with meter event type 48 (tight window) and myenergy.topups (broad window), plus direction and an emergency-credit-grant heuristic. Default returns only jumps missing at least one signal.';

REVOKE EXECUTE ON FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, boolean, integer, integer, boolean, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, boolean, integer, integer, boolean, numeric) TO public_backend, grafanareader;

CREATE OR REPLACE FUNCTION myenergy.untracked_prepay_credits(
    since        timestamptz DEFAULT NULL,
    until        timestamptz DEFAULT NULL,
    maturity     interval    DEFAULT '1 hour',
    ec_tolerance numeric     DEFAULT 0.5
)
RETURNS TABLE (
    meter_id       uuid,
    serial         text,
    meter_name     text,
    jump_at        timestamptz,
    balance_before numeric,
    balance_after  numeric,
    jump_amount    numeric,
    correlation    text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
WITH bounds AS (
    SELECT COALESCE(since, now() - interval '3 hours') AS since_ts,
           COALESCE(until, now() - interval '1 hour')  AS until_ts
)
SELECT u.meter_id,
       u.serial,
       u.meter_name,
       u.jump_at,
       u.balance_before,
       u.balance_after,
       u.jump_amount,
       u.correlation
FROM bounds b
CROSS JOIN LATERAL myenergy.uncorrelated_balance_jumps(
        from_ts              => b.since_ts - interval '1 hour',
        to_ts                => b.until_ts,
        min_abs_diff         => 1.0,
        credits_only         => true,
        event_window_minutes => 60,
        topup_window_minutes => 720,
        only_uncorrelated    => true,
        ec_tolerance         => ec_tolerance
    ) u
WHERE u.jump_at >= b.since_ts
  AND u.jump_at <= b.until_ts
  AND u.jump_at <= now() - maturity
  AND NOT u.has_topup
  AND NOT u.likely_ec_grant
ORDER BY u.jump_at DESC;
$$;

ALTER FUNCTION myenergy.untracked_prepay_credits(timestamptz, timestamptz, interval, numeric)
    OWNER TO :"adminrole";

COMMENT ON FUNCTION myenergy.untracked_prepay_credits(timestamptz, timestamptz, interval, numeric)
    IS 'Untracked prepay credits: upward balance jumps with no myenergy.topups record and no emergency-credit signature. Default window is the mature [now-3h, now-1h] slice for once-only Grafana alert evaluation.';

REVOKE EXECUTE ON FUNCTION myenergy.untracked_prepay_credits(timestamptz, timestamptz, interval, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION myenergy.untracked_prepay_credits(timestamptz, timestamptz, interval, numeric) TO public_backend, grafanareader;

COMMIT;