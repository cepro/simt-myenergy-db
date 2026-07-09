-- Verify supabase:0027_generate_quarter_tariffs_hmce_only on pg

BEGIN;

-- Confirm the function still exists and that the deploy took effect: the
-- active_esco_codes HMCE-only filter must be present in the function body.
-- (There is only one generate_new_quarter_tariffs in myenergy, so matching by
--  schema + name is unambiguous.)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'myenergy'
      AND p.proname = 'generate_new_quarter_tariffs'
      AND p.prosrc LIKE '%active_esco_codes%'
  ) THEN
    RAISE EXCEPTION 'myenergy.generate_new_quarter_tariffs is missing the active_esco_codes HMCE-only filter';
  END IF;
END $$;

ROLLBACK;
