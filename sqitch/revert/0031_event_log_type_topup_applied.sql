-- Revert supabase:0031_event_log_type_topup_applied from pg

BEGIN;

DELETE FROM flows.meter_event_log_type
WHERE id = 48 AND name = 'CREDIT_TOKEN_APPLIED';

COMMIT;