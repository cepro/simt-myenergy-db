-- Deploy supabase:0020_auth_users_triggers to pg

BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_customers_on_email_update_trigger') THEN
    CREATE TRIGGER update_customers_on_email_update_trigger
      AFTER UPDATE OF email ON auth.users
      FOR EACH ROW EXECUTE FUNCTION myenergy.customer_email_update_for_trigger();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'customer_registration_trigger') THEN
    CREATE TRIGGER customer_registration_trigger
      BEFORE INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION myenergy.customer_registration();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'customer_status_auth_users_update') THEN
    CREATE TRIGGER customer_status_auth_users_update
      AFTER UPDATE ON auth.users
      FOR EACH ROW EXECUTE FUNCTION myenergy.customer_status_update_on_auth_users_trigger();
  END IF;
END $$;

COMMIT;
