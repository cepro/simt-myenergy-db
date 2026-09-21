-- Verify supabase:0032_balance_jump_correlation on pg

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'myenergy'
          AND p.proname = 'uncorrelated_balance_jumps'
          AND p.pronargs = 9
    ) THEN
        RAISE EXCEPTION 'myenergy.uncorrelated_balance_jumps(uuid, timestamptz, timestamptz, numeric, boolean, integer, integer, boolean, numeric) is missing';
    END IF;
END;
$$;

ROLLBACK;