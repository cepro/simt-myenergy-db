-- Verify supabase:0020_auth_users_triggers on pg

BEGIN;

SELECT 1 FROM pg_trigger WHERE tgname = 'update_customers_on_email_update_trigger';
SELECT 1 FROM pg_trigger WHERE tgname = 'customer_registration_trigger';
SELECT 1 FROM pg_trigger WHERE tgname = 'customer_status_auth_users_update';

ROLLBACK;
