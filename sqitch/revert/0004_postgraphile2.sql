-- Revert supabase:0004_postgraphile2 from pg

BEGIN;


DROP POLICY "Customers and backend can update contracts" ON myenergy.contracts;
DROP POLICY "Customers and backend users can read contracts" ON myenergy.contracts;

DROP POLICY "Customers and backend can update payments" ON myenergy.payments;
DROP POLICY "Customers and backend users can read payments" ON myenergy.payments;

DROP POLICY "Customers and backend can update topups" ON myenergy.topups;
DROP POLICY "Customers and backend users can read topups" ON myenergy.topups;

DROP POLICY "Customers and backend can update solar credits topups" ON myenergy.topups_monthly_solar_credits;
DROP POLICY "Customers and backend users can read solar credits topups" ON myenergy.topups_monthly_solar_credits;

DROP POLICY "Customers and backend can update records" ON myenergy.customers;
DROP POLICY "Customers and backend users can read records" ON myenergy.customers;

DROP POLICY "Customers and backend can update customer_invites" ON myenergy.customer_invites;
DROP POLICY "Customers and backend can read customer_invites" ON myenergy.customer_invites 

COMMIT;
