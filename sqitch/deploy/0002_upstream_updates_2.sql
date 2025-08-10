-- Deploy supabase:0002_upstream_updates_2 to pg

BEGIN;

-- Create trigger function to check scheduled_at only on INSERT or when scheduled_at is updated
CREATE OR REPLACE FUNCTION myenergy.check_scheduled_at_not_in_past()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.scheduled_at IS DISTINCT FROM NEW.scheduled_at) THEN
        IF NEW.scheduled_at < now() THEN
            RAISE EXCEPTION 'scheduled_at cannot be in the past';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER payments_scheduled_at_not_in_past_trigger
    BEFORE INSERT OR UPDATE ON myenergy.payments
    FOR EACH ROW
    EXECUTE FUNCTION myenergy.check_scheduled_at_not_in_past();

-- seemed to lost this - local unit test failing.
GRANT SELECT ON flows.meter_shadows TO tableau;

COMMIT;
