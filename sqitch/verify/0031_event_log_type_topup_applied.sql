-- Verify supabase:0031_event_log_type_topup_applied on pg

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM flows.meter_event_log_type WHERE id = 48
    ) THEN
        RAISE EXCEPTION 'flows.meter_event_log_type id 48 is missing';
    END IF;
END;
$$;

ROLLBACK;