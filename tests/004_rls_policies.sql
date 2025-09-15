BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy,extensions,public;

SELECT extensions.plan(18);

SELECT is((SELECT current_role), 'tsdbadmin', 'intial role');

--
-- Check RLS policies show authorized records to customers
-- 

set role authenticated;

-- own11_13@wl.ce - WLCE / regular customer user
SELECT set_config('request.jwt.claim.email', 'own11_13@wl.ce', true);

SELECT is((SELECT count(*)::int FROM myenergy.properties), 2, 'property - owned property');
SELECT is((SELECT count(*)::int FROM myenergy.customers), 1, 'customer - self');
SELECT is((SELECT count(*)::int FROM myenergy.accounts), 4, 'account - supply and solar for 2 properties');
SELECT is((SELECT count(*)::int FROM myenergy.customer_accounts), 4, 'customer_accounts');
SELECT is((SELECT count(*)::int FROM myenergy.customer_invites), 1, 'customer_invites');
SELECT is((SELECT count(*)::int FROM myenergy.contract_terms), 5, 'contract_terms for wlce');
SELECT is((SELECT count(*)::int FROM myenergy.contracts), 4, 'contracts');
SELECT is((SELECT count(*)::int FROM myenergy.wallets), 2, 'wallet');

-- ownocc12@wl.ce - WLCE / regular user
SELECT set_config('request.jwt.claim.email', 'ownocc12@wl.ce', true);

SELECT is((SELECT count(*)::int FROM myenergy.properties), 1, 'property - owned property');
SELECT is((SELECT count(*)::int FROM myenergy.customers), 1, 'customer - self');
SELECT is((SELECT count(*)::int FROM myenergy.accounts), 2, 'accounts - supply and solar');
SELECT is((SELECT count(*)::int FROM myenergy.customer_accounts), 2, 'customer_accounts');
SELECT is((SELECT count(*)::int FROM myenergy.customer_invites), 0, 'customer_invites');
SELECT is((SELECT count(*)::int FROM myenergy.contracts), 2, 'contracts');
SELECT is((SELECT count(*)::int FROM myenergy.wallets), 1, 'wallet');

-- cepro user can see all properties
SET role authenticated;
SELECT set_config('request.jwt.claim.email', 'a@wl.ce', true);
SELECT is((SELECT count(*)::int FROM myenergy.properties), 41, 'all properties');
SELECT is((SELECT count(*)::int FROM myenergy.contract_terms), 7, 'all contract terms');

SELECT * FROM finish();
ROLLBACK;