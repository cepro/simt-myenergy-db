-- Revert supabase:0032_balance_jump_correlation from pg

BEGIN;

DROP FUNCTION IF EXISTS myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, integer, boolean);

COMMIT;