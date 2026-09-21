-- Verify supabase:0030_solar_credits_exclude_expired_contracts on pg

BEGIN;

-- The guard predicate is present in the function body (whitespace-normalized
-- so line-wrapping in the stored definition cannot break the string match)...
DO $$
DECLARE
  def text;
BEGIN
  SELECT pg_get_functiondef('myenergy.monthly_solar_credits_unapplied(text)'::regprocedure) INTO def;
  IF position('sc.end_date < current_date' in regexp_replace(lower(def), '\s+', ' ', 'g')) = 0 THEN
    RAISE EXCEPTION 'monthly_solar_credits_unapplied() does not exclude ended solar contracts';
  END IF;

  -- ...and EXECUTE is revoked from PUBLIC (anon-only access).
  IF EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE routine_schema = 'myenergy'
      AND routine_name = 'monthly_solar_credits_unapplied'
      AND grantee = 'PUBLIC' AND privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'monthly_solar_credits_unapplied() still granted to PUBLIC';
  END IF;
END $$;

ROLLBACK;
