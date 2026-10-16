-- Verify supabase:0031_balance_jump_correlation on pg

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM flows.meter_event_log_type WHERE id = 48
    ) THEN
        RAISE EXCEPTION 'flows.meter_event_log_type id 48 is missing';
    END IF;

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

    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'myenergy'
          AND p.proname = 'untracked_prepay_credits'
          AND p.pronargs = 4
    ) THEN
        RAISE EXCEPTION 'myenergy.untracked_prepay_credits(timestamptz, timestamptz, interval, numeric) is missing';
    END IF;
END;
$$;

ROLLBACK;