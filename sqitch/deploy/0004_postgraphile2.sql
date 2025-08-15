-- Deploy supabase:0004_postgraphile2 to pg

BEGIN;


--
-- Update policies that use is_backend_user - add roles public_backend and
-- grafanareader and create 'FOR UPDATE' policies for backend_user.
--


DROP POLICY "Customers can view their own accounts only" ON myenergy.accounts;

CREATE POLICY "Customers can view their own accounts only"
ON myenergy.accounts FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT customer_accounts.account FROM myenergy.customer_accounts))
);


DROP POLICY "Customers can view their own circuits only" ON myenergy.circuits;

CREATE POLICY "Customers can view their own circuits only"
ON myenergy.circuits FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT circuit_meter.circuit_id FROM myenergy.circuit_meter))
);


DROP POLICY "Customers can view their own circuit_meter records only" ON myenergy.circuit_meter;

CREATE POLICY "Customers can view their own circuit_meter records only"
ON myenergy.circuit_meter FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (meter_id IN (SELECT meters.id FROM myenergy.meters))
);


DROP POLICY "Customers can view their own contracts only" ON myenergy.contracts;

CREATE POLICY "Customers and backend can update contracts" 
ON myenergy.contracts FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT accounts.current_contract FROM myenergy.accounts WHERE accounts.id = ANY (myenergy.accounts())))
);

CREATE POLICY "Customers and backend users can read contracts" 
ON myenergy.contracts FOR SELECT TO authenticated, public_backend, grafanareader
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT accounts.current_contract FROM myenergy.accounts WHERE accounts.id = ANY (myenergy.accounts())))
);


DROP POLICY "Customers can view their own customer_accounts" ON myenergy.customer_accounts;

CREATE POLICY "Customers can view their own customer_accounts"
ON myenergy.customer_accounts FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (customer = myenergy.customer())
);


DROP POLICY "customer_invites policy" ON myenergy.customer_invites;

CREATE POLICY "customer_invites policy"
ON myenergy.customer_invites FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (customer = myenergy.customer())
);


DROP POLICY "Customers can view their own gifts" ON myenergy.gifts;

CREATE POLICY "Customers can view their own gifts"
ON myenergy.gifts FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (customer_id = myenergy.customer())
);


DROP POLICY "Customer can view their own meters" ON myenergy.meters;

CREATE POLICY "Customer can view their own meters"
ON myenergy.meters FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT properties.supply_meter FROM myenergy.properties UNION SELECT properties.solar_meter FROM myenergy.properties))
);


DROP POLICY "Customers can view their own monthly customer costs only" ON myenergy.monthly_costs;

CREATE POLICY "Customers can view their own monthly customer costs only"
ON myenergy.monthly_costs FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (customer_id = myenergy.customer())
);


DROP POLICY "Customers can view their own monthly solar credits" ON myenergy.monthly_solar_credits;

CREATE POLICY "Customers can view their own monthly solar credits"
ON myenergy.monthly_solar_credits FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (property_id IN (SELECT a.property FROM myenergy.accounts a WHERE a.id IN (SELECT ca.account FROM myenergy.customer_accounts ca WHERE ca.customer = myenergy.customer())))
);


DROP POLICY "Customers can view their own monthly usage only" ON myenergy.monthly_usage;

CREATE POLICY "Customers can view their own monthly usage only"
ON myenergy.monthly_usage FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (circuit_id IN (SELECT circuits.id FROM myenergy.circuits))
);


DROP POLICY "Customers can view their own payments only" ON myenergy.payments;

CREATE POLICY "Customers and backend can update payments" 
ON myenergy.payments FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (account IN (SELECT customer_accounts.account FROM myenergy.customer_accounts WHERE customer_accounts.customer = myenergy.customer()))
);

CREATE POLICY "Customers and backend users can read payments" 
ON myenergy.payments FOR SELECT TO authenticated, public_backend, grafanareader
USING (
    myenergy.is_backend_user() 
    OR (account IN (SELECT customer_accounts.account FROM myenergy.customer_accounts WHERE customer_accounts.customer = myenergy.customer()))
);


DROP POLICY "Customer can view solar installations for their properties" ON myenergy.solar_installation;

CREATE POLICY "Customer can view solar installations for their properties"
ON myenergy.solar_installation FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (property IN (SELECT properties.id FROM myenergy.properties))
);


DROP POLICY "Customers can view their own topups only" ON myenergy.topups;

CREATE POLICY "Customers and backend can update topups" 
ON myenergy.topups FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (meter IN (SELECT meters.id FROM myenergy.meters))
);

CREATE POLICY "Customers and backend users can read topups" 
ON myenergy.topups FOR SELECT TO authenticated, public_backend, grafanareader
USING (
    myenergy.is_backend_user() 
    OR (meter IN (SELECT meters.id FROM myenergy.meters))
);


DROP POLICY "Customers can view their own solar credits topups" ON myenergy.topups_monthly_solar_credits;

CREATE POLICY "Customers and backend can update solar credits topups" 
ON myenergy.topups_monthly_solar_credits FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (month_solar_credit_id IN (SELECT m.id FROM myenergy.monthly_solar_credits m JOIN myenergy.accounts a ON a.property = m.property_id JOIN myenergy.customer_accounts ca ON ca.account = a.id WHERE ca.customer = myenergy.customer()))
);

CREATE POLICY "Customers and backend users can read solar credits topups" 
ON myenergy.topups_monthly_solar_credits FOR SELECT TO authenticated, public_backend, grafanareader
USING (
    myenergy.is_backend_user() 
    OR (month_solar_credit_id IN (SELECT m.id FROM myenergy.monthly_solar_credits m JOIN myenergy.accounts a ON a.property = m.property_id JOIN myenergy.customer_accounts ca ON ca.account = a.id WHERE ca.customer = myenergy.customer()))
);


DROP POLICY "Customers can view their own payment topups" ON myenergy.topups_payments;

CREATE POLICY "Customers can view their own payment topups"
ON myenergy.topups_payments FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (payment_id IN (SELECT p.id FROM myenergy.payments p JOIN myenergy.accounts a ON p.account = a.id JOIN myenergy.customer_accounts ca ON ca.account = a.id WHERE ca.customer = myenergy.customer()))
);


DROP POLICY "Customers can view their own wallets only" ON myenergy.wallets;

CREATE POLICY "Customers can view their own wallets only"
ON myenergy.wallets FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT meters.wallet FROM myenergy.meters WHERE meters.id IN (SELECT properties.supply_meter FROM myenergy.properties WHERE properties.id IN (SELECT accounts.property FROM myenergy.accounts WHERE accounts.id = ANY (myenergy.accounts())))))
);

DROP POLICY "Customers can update their wallets topup preferences only" ON myenergy.wallets;

CREATE POLICY "Customers can update their wallets topup preferences only"
ON myenergy.wallets FOR UPDATE TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT meters.wallet FROM myenergy.meters WHERE meters.id IN (SELECT properties.supply_meter FROM myenergy.properties WHERE properties.id IN (SELECT accounts.property FROM myenergy.accounts))))
);


DROP POLICY "Authenticated users can read their customer_tariffs only" ON myenergy.customer_tariffs;

CREATE POLICY "Authenticated users can read their customer_tariffs only"
ON myenergy.customer_tariffs FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (customer = myenergy.customer())
);


DROP POLICY "Authenticated users can read tariffs" ON myenergy.benchmark_tariffs;

CREATE POLICY "Authenticated users can read tariffs"
ON myenergy.benchmark_tariffs FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR true
);


DROP POLICY "Authenticated users can read microgrid tariffs" ON myenergy.microgrid_tariffs;

CREATE POLICY "Authenticated users can read microgrid tariffs"
ON myenergy.microgrid_tariffs FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (esco IN (SELECT p.esco FROM myenergy.properties p WHERE p.id IN (SELECT a.property FROM myenergy.accounts a, myenergy.customer_accounts ca WHERE ca.customer = myenergy.customer() AND a.id = ca.account)))
);


DROP POLICY "Authenticated users can read solar credit tariffs" ON myenergy.solar_credit_tariffs;

CREATE POLICY "Authenticated users can read solar credit tariffs"
ON myenergy.solar_credit_tariffs FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (esco IN (SELECT p.esco FROM myenergy.properties p WHERE p.id IN (SELECT a.property FROM myenergy.accounts a, myenergy.customer_accounts ca WHERE ca.customer = myenergy.customer() AND a.id = ca.account)))
);


DROP POLICY "Users can see term escos mappings for escos they have accounts " ON myenergy.contract_terms_esco;

CREATE POLICY "Users can see term escos mappings for escos they have accounts "
ON myenergy.contract_terms_esco FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (esco IN (SELECT properties.esco FROM myenergy.properties WHERE properties.id IN (SELECT accounts.property FROM myenergy.accounts WHERE accounts.id IN (SELECT ca.account FROM myenergy.customer_accounts ca WHERE ca.customer = myenergy.customer()))))
);


--
-- Extend these to UPDATE as well - previously worked via BypassRLS on backend_user
-- 

DROP POLICY "Customers can read their own and property owners records" ON myenergy.customers;

CREATE POLICY "Customers and backend can update records" 
ON myenergy.customers FOR UPDATE TO authenticated, public_backend
USING (
    myenergy.is_backend_user() 
    OR (email = auth.session_email()) 
    OR (id IN (SELECT myenergy.get_property_owners_for_auth_user(auth.session_email())))
);

CREATE POLICY "Customers and backend users can read records" 
ON myenergy.customers FOR SELECT TO authenticated, public_backend, grafanareader
USING (
    myenergy.is_backend_user() 
    OR (email = auth.session_email()) 
    OR (id IN (SELECT myenergy.get_property_owners_for_auth_user(auth.session_email())))
);



GRANT USAGE ON SCHEMA auth TO public_backend;


COMMIT;
