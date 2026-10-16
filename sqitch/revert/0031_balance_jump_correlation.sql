-- Revert supabase:0031_balance_jump_correlation from pg

BEGIN;

DROP FUNCTION IF EXISTS myenergy.untracked_prepay_credits(timestamptz, timestamptz, interval, numeric);

DROP FUNCTION IF EXISTS myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, boolean, integer, integer, boolean, numeric);

DELETE FROM flows.meter_event_log_type
WHERE id = 48 AND name = 'CREDIT_TOKEN_APPLIED';

COMMIT;