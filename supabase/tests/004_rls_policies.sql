BEGIN;
SELECT plan(18);

SET search_path TO extensions,public;

SELECT is((SELECT current_role), 'postgres', 'intial role');

--
-- Check RLS policies show authorized records to customers
-- 

set role authenticated;

-- own11_13@wl.ce - WLCE / regular customer user
SELECT set_config('request.jwt.claim.email', 'own11_13@wl.ce', true);

SELECT is((SELECT count(*)::int FROM properties), 2, 'property - owned property');
SELECT is((SELECT count(*)::int FROM customers), 1, 'customer - self');
SELECT is((SELECT count(*)::int FROM accounts), 4, 'account - supply and solar for 2 properties');
SELECT is((SELECT count(*)::int FROM customer_accounts), 4, 'customer_accounts');
SELECT is((SELECT count(*)::int FROM customer_invites), 0, 'customer_invites');
SELECT is((SELECT count(*)::int FROM contract_terms), 5, 'contract_terms for wlce');
SELECT is((SELECT count(*)::int FROM contracts), 4, 'contracts');
SELECT is((SELECT count(*)::int FROM wallets), 2, 'wallet');

-- ownocc12@wl.ce - WLCE / regular user
SELECT set_config('request.jwt.claim.email', 'ownocc12@wl.ce', true);

SELECT is((SELECT count(*)::int FROM properties), 1, 'property - owned property');
SELECT is((SELECT count(*)::int FROM customers), 1, 'customer - self');
SELECT is((SELECT count(*)::int FROM accounts), 2, 'accounts - supply and solar');
SELECT is((SELECT count(*)::int FROM customer_accounts), 2, 'customer_accounts');
SELECT is((SELECT count(*)::int FROM customer_invites), 0, 'customer_invites');
SELECT is((SELECT count(*)::int FROM contracts), 2, 'contracts');
SELECT is((SELECT count(*)::int FROM wallets), 1, 'wallet');

-- cepro user can see all properties
SET role authenticated;
SELECT set_config('request.jwt.claim.email', 'a@wl.ce', true);
SELECT is((SELECT count(*)::int FROM properties), 41, 'all properties');
SELECT is((SELECT count(*)::int FROM contract_terms), 7, 'all contract terms');

SELECT * FROM finish();
ROLLBACK;