-- Revert supabase:0013_secure_notify from pg

BEGIN;

DROP TRIGGER IF EXISTS notify_topup_scheduled_trigger ON myenergy.topups;
DROP FUNCTION IF EXISTS myenergy.notify_topup_scheduled;

DROP TRIGGER IF EXISTS notify_topup_completed_trigger ON myenergy.topups;
DROP FUNCTION IF EXISTS myenergy.notify_topup_completed;

DROP FUNCTION IF EXISTS myenergy.notify;

DROP TABLE IF EXISTS myenergy.postgres_notifications_outbox;

COMMIT;
