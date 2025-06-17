-- Fixed test in 006_customer_status.sql
BEGIN;
SELECT plan(35); -- Updated plan count to include new tests

SET search_path TO extensions,public;



SELECT is((SELECT count(*)::int FROM customers where status = 'pending'), 42, 'pending customers returned');
SELECT is((SELECT count(*)::int FROM customers where status = 'preonboarding'), 0, 'preonboarding customers returned');
-- ownocc12@wl.ce   - all flags set and prepay meter on but supply contract not yet signed so still onboarding
SELECT is((SELECT count(*)::int FROM customers where status = 'onboarding'), 1, 'onboarding customers returned');
-- occ11@wl.ce      - supply contract signed but meter not in prepay mode - thus prelive
-- occ13@wl.ce      - same as occ11@wl.ce
SELECT is((SELECT count(*)::int FROM customers where status = 'prelive'), 2, 'prelive customers returned');
-- a@wl.ce          - cepro admin user - always live
-- own11_13@wl.ce   - owner / not occupier - signed both solar contracts - status not effected by supply flag 
SELECT is((SELECT count(*)::int FROM customers where status = 'live'), 2, 'live customers returned');


--
-- Prepare reusable statements
--

PREPARE cust_status(text) AS SELECT status::text FROM customers WHERE email = $1;

PREPARE meter_prepay_update(boolean, text) AS 
    UPDATE meters m
    SET prepay_enabled = $1
    FROM properties p
    WHERE p.supply_meter = m.id
    AND p.id IN (
        SELECT a.property
        FROM accounts a
        JOIN customer_accounts ca ON ca.account = a.id
        JOIN customers c ON c.id = ca.customer
        WHERE c.email = $2
    );

PREPARE sign_contracts(text) AS 
    UPDATE contracts set signed_date = '2024-01-01 00:00 +00'
    WHERE id in (select current_contract from accounts where id in (
        select account from customer_accounts where customer in (
            select id from customers where email = $1
        )
    )) and "type" in ('supply', 'solar'); -- both contracts



--
-- Owner (non occupier) Test
--

-- Setup own11_13@wl.ce as a live customer - sign contracts and set all flags as needed:

EXECUTE sign_contracts('own11_13@wl.ce');

UPDATE customers SET
    has_payment_method = true,
    allow_onboard_transition = true,
    confirmed_details_at = '2024-01-01 00:00 +00'
WHERE email = 'own11_13@wl.ce';

EXECUTE meter_prepay_update(true, 'own11_13@wl.ce');

SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('live') $$, 'customer is live');

-- Now toggle different flags and check status updates as expected:

-- has_payment_method
UPDATE customers SET has_payment_method = false WHERE email = 'own11_13@wl.ce';
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('onboarding') $$, 'customer is onboarding');

UPDATE customers SET has_payment_method = true WHERE email = 'own11_13@wl.ce';
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('live') $$, 'customer is live after has_payment_method');

-- confirmed_details_at
UPDATE customers SET confirmed_details_at = null WHERE email = 'own11_13@wl.ce';
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('onboarding') $$, 'customer is onboarding');

UPDATE customers SET confirmed_details_at = '2024-01-01 00:00 +00' WHERE email = 'own11_13@wl.ce';
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('live') $$, 'customer is live after confirmed_details_at');

-- allow_onboard_transition
UPDATE customers SET allow_onboard_transition = false WHERE email = 'own11_13@wl.ce';
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('preonboarding') $$, 'customer is preonboarding');

UPDATE customers SET allow_onboard_transition = true WHERE email = 'own11_13@wl.ce';
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('live') $$, 'customer is live after allow_onboard_transition');

-- Test prelive vs live transitions

EXECUTE meter_prepay_update(false, 'own11_13@wl.ce');

-- STILL live because supply prepay_enabled status doesn't effect the owner 
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('live') $$, 'owner still live when prepay_enabled is false');

EXECUTE meter_prepay_update(true, 'own11_13@wl.ce');

-- Verify customer transitions back to live status
SELECT results_eq('cust_status(''own11_13@wl.ce'')', $$ VALUES('live') $$, 'owner still live when prepay_enabled is true');


--
-- Occupier only Test
--

EXECUTE sign_contracts('occ11@wl.ce');

UPDATE customers SET
    has_payment_method = true,
    allow_onboard_transition = true,
    confirmed_details_at = '2024-01-01 00:00 +00'
WHERE email = 'occ11@wl.ce';

EXECUTE meter_prepay_update(true, 'occ11@wl.ce');

-- explicit recompute customer_status
UPDATE customers SET status = public.customer_status(customers) WHERE email = 'occ11@wl.ce';

SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('live') $$, 'customer is live after meter prepay on (ownocc11)');

-- Now toggle different flags and check status updates as expected:

-- has_payment_method
UPDATE customers SET has_payment_method = false WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('onboarding') $$, 'customer is onboarding');

UPDATE customers SET has_payment_method = true WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('live') $$, 'customer is live after has_payment_method');

-- confirmed_details_at
UPDATE customers SET confirmed_details_at = null WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('onboarding') $$, 'customer is onboarding');

UPDATE customers SET confirmed_details_at = '2024-01-01 00:00 +00' WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('live') $$, 'customer is live after confirmed_details_at');

-- allow_onboard_transition
UPDATE customers SET allow_onboard_transition = false WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('preonboarding') $$, 'customer is preonboarding');

UPDATE customers SET allow_onboard_transition = true WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('live') $$, 'customer is live after allow_onboard_transition');

-- Test prelive vs live transitions

-- moves to prelive when the meter is not in prepay mode
EXECUTE meter_prepay_update(false, 'occ11@wl.ce');

-- explicit recompute customer_status
UPDATE customers SET status = public.customer_status(customers) WHERE email = 'occ11@wl.ce';

SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('prelive') $$, 'customer is prelive when prepay_enabled is false');

EXECUTE meter_prepay_update(true, 'occ11@wl.ce');
UPDATE customers SET status = public.customer_status(customers) WHERE email = 'occ11@wl.ce';
SELECT results_eq('cust_status(''occ11@wl.ce'')', $$ VALUES('live') $$, 'customer is live when prepay_enabled is true');



--
-- Owner Occupier Test
--

EXECUTE sign_contracts('ownocc12@wl.ce');

UPDATE customers SET
    has_payment_method = true,
    allow_onboard_transition = true,
    confirmed_details_at = '2024-01-01 00:00 +00'
WHERE email = 'ownocc12@wl.ce';

EXECUTE meter_prepay_update(true, 'ownocc12@wl.ce');
UPDATE customers SET status = public.customer_status(customers) WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('live') $$, 'customer is live after meter prepay on (ownocc12)');

-- Now toggle different flags and check status updates as expected:

-- has_payment_method
UPDATE customers SET has_payment_method = false WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('onboarding') $$, 'customer is onboarding');

UPDATE customers SET has_payment_method = true WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('live') $$, 'customer is live after has_payment_method');

-- confirmed_details_at
UPDATE customers SET confirmed_details_at = null WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('onboarding') $$, 'customer is onboarding');

UPDATE customers SET confirmed_details_at = '2024-01-01 00:00 +00' WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('live') $$, 'customer is live after confirmed_details_at');

-- allow_onboard_transition
UPDATE customers SET allow_onboard_transition = false WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('preonboarding') $$, 'customer is preonboarding');

UPDATE customers SET allow_onboard_transition = true WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('live') $$, 'customer is live after allow_onboard_transition');

-- Test prelive vs live transitions

-- moves to prelive when the meter is not in prepay mode
EXECUTE meter_prepay_update(false, 'ownocc12@wl.ce');

-- explicit recompute customer_status
UPDATE customers SET status = public.customer_status(customers) WHERE email = 'ownocc12@wl.ce';

SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('prelive') $$, 'customer is prelive when prepay_enabled is false');

EXECUTE meter_prepay_update(true, 'ownocc12@wl.ce');
UPDATE customers SET status = public.customer_status(customers) WHERE email = 'ownocc12@wl.ce';
SELECT results_eq('cust_status(''ownocc12@wl.ce'')', $$ VALUES('live') $$, 'customer is live when prepay_enabled is true');


--
-- Admin user always live:
--

PREPARE admin_status AS SELECT status::text FROM customers WHERE email = 'a@wl.ce';
SELECT results_eq('admin_status', $$ VALUES('live') $$, 'admin initially live from seed');

-- turn off flags that effect normal customers:
UPDATE customers SET allow_onboard_transition = false WHERE email = 'a@wl.ce';
UPDATE customers SET has_payment_method = false WHERE email = 'a@wl.ce';
SELECT results_eq('admin_status', $$ VALUES('live') $$, 'admin still live');

-- also test that setting prepay_enabled to false doesn't affect cepro_user
EXECUTE meter_prepay_update(false, 'a@wl.ce');

SELECT results_eq('admin_status', $$ VALUES('live') $$, 'admin still live even with prepay_enabled false');



SELECT * FROM finish();
ROLLBACK;