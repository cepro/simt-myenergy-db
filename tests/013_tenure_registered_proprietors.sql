BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, extensions, public;

SELECT plan(6);

SELECT is((SELECT current_role), 'tsdbadmin', 'initial role');

--
-- Structural: tenure_for_property + the registered_proprietors trigger exist.
--

SELECT has_function('myenergy', 'tenure_for_property', ARRAY['uuid'],
    'tenure_for_property(uuid) exists');

SELECT has_trigger('myenergy', 'registered_proprietors', 'update_property_tenure_registered_proprietors',
    'update_property_tenure fires on registered_proprietors');

--
-- Functional: a supply-only property (no solar account) whose registered
-- proprietor differs from its occupier must be classified
-- separate_owner_and_occupier, and changing the registered_proprietor must
-- re-evaluate tenure. This is the exact case the pre-0028 trigger could not
-- handle: no owner row in customer_accounts (the 0023 sync_rp_to_ca is a no-op
-- without a solar account), so the old logic fell through to
-- single_owner_occupier and never fired on registered_proprietors changes.
--

-- ids for the test property + its supply account
CREATE TEMP TABLE tt(prop uuid, acct uuid);

-- Two test customers: an occupier and a different person (the owner).
INSERT INTO myenergy.customers (fullname, email, created_at, status, cepro_user, has_payment_method, allow_onboard_transition)
VALUES
    ('Tenure Test Occupier', 'tenure_test_occ@example.com', now(), 'pending', false, true, true),
    ('Tenure Test Owner',    'tenure_test_own@example.com', now(), 'pending', false, true, true);

INSERT INTO auth.users (instance_id, id, aud, "role", email, encrypted_password, email_confirmed_at, created_at, updated_at)
SELECT
    '00000000-0000-0000-0000-000000000000',
    c.id, 'authenticated', 'authenticated', c.email,
    '$2a$10$RpraqBFICv/T3vENeJE1UeEYzTZ8GO9opgaJ6janMS1ro6a6X8qN.',
    now(), now(), now()
FROM myenergy.customers c
WHERE c.email IN ('tenure_test_occ@example.com', 'tenure_test_own@example.com')
ON CONFLICT (id) DO NOTHING;

-- A supply-only property, capture its id.
WITH ins AS (
    INSERT INTO myenergy.properties (esco)
    SELECT id FROM myenergy.escos LIMIT 1
    RETURNING id
)
INSERT INTO tt (prop) SELECT id FROM ins;

-- Its supply account, capture its id.
WITH ins AS (
    INSERT INTO myenergy.accounts (property, type)
    SELECT prop, 'supply'::myenergy.account_type_enum FROM tt
    RETURNING id
)
UPDATE tt SET acct = (SELECT id FROM ins);

-- The occupier lives on the supply account.
INSERT INTO myenergy.customer_accounts (customer, account, role)
SELECT c.id, tt.acct, 'occupier'::myenergy.account_role_type_enum
FROM myenergy.customers c CROSS JOIN tt
WHERE c.email = 'tenure_test_occ@example.com';

-- Case 1: registered_proprietor == occupier  =>  single_owner_occupier.
INSERT INTO myenergy.registered_proprietors (property, customer, tenure_type)
SELECT tt.prop, c.id, 'joint_tenant'
FROM myenergy.customers c CROSS JOIN tt
WHERE c.email = 'tenure_test_occ@example.com';

SELECT is(
    (SELECT tenure FROM myenergy.properties WHERE id = (SELECT prop FROM tt)),
    'single_owner_occupier'::myenergy.property_tenure_enum,
    'RP == occupier on a supply-only property -> single_owner_occupier'
);

-- Case 2: change the registered_proprietor to a different person => separate.
DELETE FROM myenergy.registered_proprietors WHERE property = (SELECT prop FROM tt);

INSERT INTO myenergy.registered_proprietors (property, customer, tenure_type)
SELECT tt.prop, c.id, 'joint_tenant'
FROM myenergy.customers c CROSS JOIN tt
WHERE c.email = 'tenure_test_own@example.com';

SELECT is(
    (SELECT tenure FROM myenergy.properties WHERE id = (SELECT prop FROM tt)),
    'separate_owner_and_occupier'::myenergy.property_tenure_enum,
    'RP != occupier on a supply-only property -> separate (RP trigger re-evaluated tenure)'
);

SELECT is(
    (SELECT myenergy.tenure_for_property(prop) FROM tt),
    'separate_owner_and_occupier'::myenergy.property_tenure_enum,
    'tenure_for_property agrees with the stored tenure'
);

--
-- Cleanup
--
DELETE FROM myenergy.registered_proprietors WHERE property = (SELECT prop FROM tt);
DELETE FROM myenergy.customer_accounts WHERE account = (SELECT acct FROM tt);
DELETE FROM myenergy.accounts WHERE id = (SELECT acct FROM tt);
DELETE FROM myenergy.properties WHERE id = (SELECT prop FROM tt);
DELETE FROM myenergy.customers WHERE email IN ('tenure_test_occ@example.com', 'tenure_test_own@example.com');
DELETE FROM auth.users WHERE email IN ('tenure_test_occ@example.com', 'tenure_test_own@example.com');

DROP TABLE tt;

SELECT * FROM finish();
ROLLBACK;
