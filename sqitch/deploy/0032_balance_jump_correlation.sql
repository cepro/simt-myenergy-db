-- Deploy supabase:0032_balance_jump_correlation to pg
-- Diagnostic function for investigating unexpected prepay balance jumps.
--
-- Lists jumps in flows.meter_prepay_balance and flags whether each is
-- correlated with a topup, i.e. either:
--   * a flows.meter_event_log row with event_type = 48 (CREDIT_TOKEN_APPLIED)
--     within the window, or
--   * a myenergy.topups row (used_at) for the same meter within the window.
--
-- A jump correlated with neither is suspicious - most likely an untracked
-- emergency-credit / debt-recovery adjustment, which the meter does not appear
-- to log as an event. The function reports the two flags plus a `correlation`
-- label so callers can find jumps missing one, the other, or both.
--
-- With the default only_uncorrelated := true only jumps that are missing at
-- least one signal are returned; pass false to see every jump with its flags.
--
-- NOTE: flows.meter_prepay_balance is a Timescale hypertable. On MGF always
-- pass a meter and/or a time range.

BEGIN;

CREATE OR REPLACE FUNCTION myenergy.uncorrelated_balance_jumps(
    meter_id_in       uuid        DEFAULT NULL,
    from_ts           timestamptz DEFAULT NULL,
    to_ts             timestamptz DEFAULT NULL,
    min_abs_diff      numeric     DEFAULT 1.0,
    window_hours      integer     DEFAULT 24,
    only_uncorrelated boolean     DEFAULT true
)
RETURNS TABLE (
    meter_id       uuid,
    serial         text,
    meter_name     text,
    jump_at        timestamptz,
    balance_before numeric,
    balance_after  numeric,
    jump_amount    numeric,
    has_event_48   boolean,
    has_topup      boolean,
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
                 AND e.timestamp BETWEEN j.jump_at - make_interval(mins => window_hours * 30)
                                     AND j.jump_at + make_interval(mins => window_hours * 30)
           ) AS has_event_48,
           EXISTS (
               SELECT 1
               FROM myenergy.topups t
               JOIN myenergy.meters m ON m.id = t.meter
               WHERE m.serial = reg.serial
                 AND t.used_at BETWEEN j.jump_at - make_interval(mins => window_hours * 30)
                                   AND j.jump_at + make_interval(mins => window_hours * 30)
           ) AS has_topup
    FROM jumps j
    JOIN flows.meter_registry reg ON reg.id = j.meter_id
)
SELECT f.meter_id,
       f.serial,
       f.meter_name,
       f.jump_at,
       f.balance_before,
       f.balance_after,
       f.jump_amount,
       f.has_event_48,
       f.has_topup,
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

ALTER FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, integer, boolean)
    OWNER TO :"adminrole";

COMMENT ON FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, integer, boolean)
    IS 'List prepay balance jumps and flag whether each is correlated with a meter event type 48 and/or a myenergy.topups record within window_hours. Default returns only jumps missing at least one signal.';

REVOKE EXECUTE ON FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, integer, boolean) TO public_backend, grafanareader;

COMMIT;