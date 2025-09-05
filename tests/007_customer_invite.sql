BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy,extensions,public;

SELECT extensions.plan(2);


SELECT is((SELECT count(*)::int FROM customer_invites), 2, 'customer_invites total');
SELECT is(
    (SELECT count(*)::int FROM customer_invites WHERE invite_url LIKE 'http://0.0.0.0:4242/invite/%'),
    2,
    'customer_invites all have generated invite_url'
);

SELECT * FROM finish();
ROLLBACK;
