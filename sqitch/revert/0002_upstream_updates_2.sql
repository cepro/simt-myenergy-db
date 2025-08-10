-- Revert supabase:0002_upstream_updates_2 from pg

BEGIN;

DROP TRIGGER payments_scheduled_at_not_in_past_trigger ON myenergy.payments;
DROP FUNCTION myenergy.check_scheduled_at_not_in_past;

COMMIT;
