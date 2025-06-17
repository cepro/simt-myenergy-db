BEGIN;
SELECT plan(2);

SET search_path TO extensions,public;

SELECT is((SELECT count(*)::int FROM customer_invites), 2, 'customer_invites total');
SELECT is(
    (SELECT count(*)::int FROM customer_invites WHERE invite_url LIKE 'http://0.0.0.0:4242/invite/%'),
    2,
    'customer_invites all have generated invite_url'
);

SELECT * FROM finish();
ROLLBACK;
