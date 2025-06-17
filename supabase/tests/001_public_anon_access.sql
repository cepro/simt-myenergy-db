BEGIN;
SELECT plan(10);

set role anon;

-- anon can read
SELECT is((SELECT count(*)::int FROM sites), 3, '3 sites returned');
SELECT is((SELECT count(*)::int FROM escos), 9, '9 escos returned');

-- anon can't read
SELECT is((SELECT count(*)::int FROM accounts), 0, 'no accounts returned');
SELECT is((SELECT count(*)::int FROM customers), 0, 'no customers returned');
SELECT is((SELECT count(*)::int FROM customer_accounts), 0, 'no customer_accounts returned');
SELECT is((SELECT count(*)::int FROM customer_invites), 0, 'no customer_invites returned');
SELECT is((SELECT count(*)::int FROM properties), 0, 'no properties returned');
SELECT is((SELECT count(*)::int FROM contracts), 0, 'no contracts returned');
SELECT is((SELECT count(*)::int FROM contract_terms), 0, 'no contract_terms returned');
SELECT is((SELECT count(*)::int FROM wallets), 0, 'no wallets returned');

-- TODO: add more once seed.sql has been updated with more data

SELECT * FROM finish();
ROLLBACK;
