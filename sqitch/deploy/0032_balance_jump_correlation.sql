-- Deploy supabase:0032_balance_jump_correlation to pg
-- Diagnostic function for investigating unexpected prepay balance jumps.
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

BEGIN;

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

COMMIT;