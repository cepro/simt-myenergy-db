BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, extensions, public;

SELECT plan(6);

SELECT is((SELECT current_role), 'tsdbadmin', 'initial role');

--
-- 0029 replay protection, part 2: a payment may be linked to at most one topup.
-- The composite PK (payment_id, topup_id) does not enforce this, and the
-- check-then-insert COUNT trigger from 0000 (topups_payments_check_payment_unique)
-- is racy under concurrent inserts. 0029 adds the unique index
-- topups_payments_payment_id_key as the real, atomic guard.
--

-- Structural: the unique index exists.
SELECT is(
    (SELECT count(*)::int FROM pg_indexes
      WHERE schemaname = 'myenergy' AND tablename = 'topups_payments'
        AND indexname = 'topups_payments_payment_id_key'),
    1::int,
    'unique index topups_payments_payment_id_key exists'
);

-- Fixture ids.
CREATE TEMP TABLE tt(prop uuid, acct uuid, payment1 uuid, payment2 uuid, meter uuid,
    topup1 uuid, topup2 uuid, topup3 uuid);

INSERT INTO tt VALUES (
    'd290f1ee-6c54-4b01-9d0f-002900000001', -- prop
    'd290f1ee-6c54-4b01-9d0f-002900000002', -- acct
    'd290f1ee-6c54-4b01-9d0f-002900000003', -- payment1
    'd290f1ee-6c54-4b01-9d0f-002900000004', -- payment2
    'd290f1ee-6c54-4b01-9d0f-002900000005', -- meter
    'd290f1ee-6c54-4b01-9d0f-002900000006', -- topup1
    'd290f1ee-6c54-4b01-9d0f-002900000007', -- topup2
    'd290f1ee-6c54-4b01-9d0f-002900000008'  -- topup3
);

INSERT INTO myenergy.properties (id, updated_at)
SELECT prop, now() FROM tt;

INSERT INTO myenergy.accounts (id, property)
SELECT acct, prop FROM tt;

INSERT INTO myenergy.meters (id, serial)
SELECT meter, 'TEST-0029-UNIQ' FROM tt;

INSERT INTO myenergy.payments (id, account, amount_pence, description, created_at)
SELECT payment1, acct, 1000, '0029 unique guard test', now() FROM tt;

INSERT INTO myenergy.payments (id, account, amount_pence, description, created_at)
SELECT payment2, acct, 1234, '0029 unique guard test 2', now() + interval '1 second' FROM tt;

INSERT INTO myenergy.topups (id, meter, amount_pence, status, source, created_at)
SELECT topup1, meter, 1234, 'pending', 'payment', now() FROM tt;

INSERT INTO myenergy.topups (id, meter, amount_pence, status, source, created_at)
SELECT topup2, meter, 1234, 'pending', 'payment', now() + interval '1 second' FROM tt;

INSERT INTO myenergy.topups (id, meter, amount_pence, status, source, created_at)
SELECT topup3, meter, 1234, 'pending', 'payment', now() + interval '2 seconds' FROM tt;

--
-- Functional 1: with the racy 0000 COUNT trigger disabled, the unique index
-- alone must reject a second link for the same payment.
--

ALTER TABLE myenergy.topups_payments DISABLE TRIGGER topups_payments_check_payment_unique_trigger;

SELECT lives_ok(
    format('INSERT INTO myenergy.topups_payments (payment_id, topup_id) VALUES (%L, %L)',
           (SELECT payment1 FROM tt), (SELECT topup1 FROM tt)),
    'first topups_payments link for a payment is accepted'
);

SELECT throws_ok(
    format('INSERT INTO myenergy.topups_payments (payment_id, topup_id) VALUES (%L, %L)',
           (SELECT payment1 FROM tt), (SELECT topup2 FROM tt)),
    '23505',
    'duplicate key value violates unique constraint "topups_payments_payment_id_key"',
    'second link for the same payment violates topups_payments_payment_id_key'
);

--
-- Functional 2: with the trigger re-enabled, both layers are active - the
-- trigger rejects a duplicate before the index is reached. This documents that
-- the trigger remains as a first line and the index as the race-safe backstop.
--

ALTER TABLE myenergy.topups_payments ENABLE TRIGGER topups_payments_check_payment_unique_trigger;

SELECT lives_ok(
    format('INSERT INTO myenergy.topups_payments (payment_id, topup_id) VALUES (%L, %L)',
           (SELECT payment2 FROM tt), (SELECT topup1 FROM tt)),
    'first link for a second payment is accepted'
);

SELECT throws_ok(
    format('INSERT INTO myenergy.topups_payments (payment_id, topup_id) VALUES (%L, %L)',
           (SELECT payment2 FROM tt), (SELECT topup3 FROM tt)),
    'P0001',
    format('Duplicate payment_id: %s. Each payment can only be linked to one topup.',
           (SELECT payment2 FROM tt)),
    'the 0000 check trigger still raises on a duplicate payment_id'
);

SELECT * FROM finish();
ROLLBACK;