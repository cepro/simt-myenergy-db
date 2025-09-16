-- Revert supabase:0006_public_backend_mutations_policy from pg

BEGIN;

DROP POLICY IF EXISTS "Customers and backend can insert topups" ON myenergy.topups;
DROP POLICY IF EXISTS "Customers and backend can update topups" ON myenergy.topups;

DROP POLICY IF EXISTS "Customers and backend can insert payments" ON myenergy.payments;
DROP POLICY IF EXISTS "Customers and backend can update payments" ON myenergy.payments;

DROP POLICY IF EXISTS "Customers and backend can insert topups_gifts" ON myenergy.topups_gifts;
DROP POLICY IF EXISTS "Customers and backend can insert topups_payments" ON myenergy.topups_payments;
DROP POLICY IF EXISTS "Customers and backend can insert topups_monthly_solar_credits" ON myenergy.topups_monthly_solar_credits;

-- Restore previous policies

CREATE POLICY "Customers and backend can update topups" 
ON myenergy.topups FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (meter IN (SELECT meters.id FROM myenergy.meters))
);

CREATE POLICY "Customers and backend can update payments" 
ON myenergy.payments FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (account IN (SELECT customer_accounts.account FROM myenergy.customer_accounts WHERE customer_accounts.customer = myenergy.customer()))
);

CREATE POLICY "Customers and backend can update solar credits topups" 
ON myenergy.topups_monthly_solar_credits FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (month_solar_credit_id IN (SELECT m.id FROM myenergy.monthly_solar_credits m JOIN myenergy.accounts a ON a.property = m.property_id JOIN myenergy.customer_accounts ca ON ca.account = a.id WHERE ca.customer = myenergy.customer()))
);

COMMIT;
