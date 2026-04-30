-- Revert supabase:0020_auth_users_triggers from pg

BEGIN;

DROP TRIGGER IF EXISTS update_customers_on_email_update_trigger ON auth.users;
DROP TRIGGER IF EXISTS customer_registration_trigger ON auth.users;
DROP TRIGGER IF EXISTS customer_status_auth_users_update ON auth.users;

COMMIT;
