-- Deploy supabase:0007_fix_scheduled_at_check to pg

BEGIN;

-- Update function to only apply on updates where the scheduled_at has changed
-- This is inline with recent supabase hosted db change.

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

COMMIT;
