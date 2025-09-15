-- Revert supabase:0006_public_backend_mutations_policy from pg

BEGIN;

DROP POLICY IF EXISTS "Public backend can insert payments" ON myenergy.payments;
DROP POLICY IF EXISTS "Public backend can update payments" ON myenergy.payments;

DROP POLICY IF EXISTS "Public backend can insert topups" ON myenergy.topups;
DROP POLICY IF EXISTS "Public backend can update topups" ON myenergy.topups;

DROP POLICY IF EXISTS "Public backend can insert topups_payments" ON myenergy.topups_payments;
DROP POLICY IF EXISTS "Public backend can update topups_payments" ON myenergy.topups_payments;

DROP POLICY IF EXISTS "Public backend can insert topups_monthly_solar_credits" ON myenergy.topups_monthly_solar_credits;
DROP POLICY IF EXISTS "Public backend can update topups_monthly_solar_credits" ON myenergy.topups_monthly_solar_credits;

DROP POLICY IF EXISTS "Public backend can insert topups_gifts" ON myenergy.topups_gifts;
DROP POLICY IF EXISTS "Public backend can update topups_gifts" ON myenergy.topups_gifts;

COMMIT;
