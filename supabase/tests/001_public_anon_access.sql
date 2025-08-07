BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, public, extensions;

SELECT extensions.plan(9);

set role supabase_admin;
set role anon;

-- anon can read
SELECT is((SELECT count(*)::int FROM myenergy.escos), 9, '9 escos returned');

-- anon can't read
SELECT is((SELECT count(*)::int FROM myenergy.accounts), 0, 'no accounts returned');
SELECT is((SELECT count(*)::int FROM myenergy.customers), 0, 'no customers returned');
SELECT is((SELECT count(*)::int FROM myenergy.customer_accounts), 0, 'no customer_accounts returned');
SELECT is((SELECT count(*)::int FROM myenergy.customer_invites), 0, 'no customer_invites returned');
SELECT is((SELECT count(*)::int FROM myenergy.properties), 0, 'no properties returned');
SELECT is((SELECT count(*)::int FROM myenergy.contracts), 0, 'no contracts returned');
SELECT is((SELECT count(*)::int FROM myenergy.contract_terms), 0, 'no contract_terms returned');
SELECT is((SELECT count(*)::int FROM myenergy.wallets), 0, 'no wallets returned');

-- TODO: add more once seed.sql has been updated with more data

SELECT * FROM finish();
ROLLBACK;
