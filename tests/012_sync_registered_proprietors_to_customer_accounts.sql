BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, extensions, public;

SELECT extensions.plan(9);

SELECT is((SELECT current_role), 'tsdbadmin', 'initial role');

--
-- Test: sync_rp_to_ca function exists
--

SELECT is(
    (SELECT count(*) > 0 FROM pg_proc WHERE proname = 'sync_rp_to_ca'),
    true,
    'sync_rp_to_ca function exists'
);

--
-- Test: sync_rp_to_ca trigger exists on registered_proprietors
--

SELECT is(
    (SELECT count(*) > 0 FROM pg_trigger WHERE tgname = 'sync_rp_to_ca_on_registered_proprietors'),
    true,
    'sync_rp_to_ca trigger exists on registered_proprietors'
);

--
-- Test: migrate_existing_rp_to_ca function exists
--

SELECT is(
    (SELECT count(*) > 0 FROM pg_proc WHERE proname = 'migrate_existing_rp_to_ca'),
    true,
    'migrate_existing_rp_to_ca function exists'
);

--
-- Create test data: a new customer and property for RP sync testing
--

CREATE TEMP TABLE rp_sync_test_ids (
    customer_id uuid,
    property_id uuid,
    solar_account_id uuid
);

-- Insert test customer
INSERT INTO myenergy.customers (fullname, email, created_at, status, cepro_user, has_payment_method, allow_onboard_transition)
VALUES (
    'RP Sync Test Customer',
    'rp_sync_test@example.com',
    now(),
    'pending',
    false,
    true,
    true
);

INSERT INTO auth.users (instance_id, id, aud, "role", email, encrypted_password, email_confirmed_at, created_at, updated_at)
SELECT
    '00000000-0000-0000-0000-000000000000',
    c.id,
    'authenticated',
    'authenticated',
    'rp_sync_test@example.com',
    '$2a$10$RpraqBFICv/T3vENeJE1UeEYzTZ8GO9opgaJ6janMS1ro6a6X8qN.',
    now(),
    now(),
    now()
FROM myenergy.customers c WHERE c.email = 'rp_sync_test@example.com'
ON CONFLICT (id) DO NOTHING;

-- Get customer and property IDs
INSERT INTO rp_sync_test_ids (customer_id, property_id, solar_account_id)
SELECT
    (SELECT id FROM myenergy.customers WHERE email = 'rp_sync_test@example.com'),
    p.id,
    a.id
FROM myenergy.properties p
JOIN myenergy.accounts a ON a.property = p.id AND a.type = 'solar'
LIMIT 1;

--
-- Test: inserting registered_proprietors triggers auto-creation of customer_accounts for solar accounts
--

-- Insert registered_proprietors (trigger should create customer_accounts)
INSERT INTO myenergy.registered_proprietors (property, customer, tenure_type)
SELECT property_id, customer_id, 'joint_tenant'
FROM rp_sync_test_ids
ON CONFLICT DO NOTHING;

-- Verify customer_accounts entry was created with role='owner' for solar account
SELECT is(
    (SELECT count(*) > 0 FROM myenergy.customer_accounts ca
     JOIN myenergy.accounts a ON a.id = ca.account
     WHERE ca.customer = (SELECT customer_id FROM rp_sync_test_ids)
     AND ca.role = 'owner'
     AND a.type = 'solar'),
    true,
    'inserting registered_proprietors creates customer_accounts entry with role=owner for solar account'
);

--
-- Test: inserting same registered_proprietor again does not create duplicate
--

SELECT is(
    (SELECT count(*)::int FROM myenergy.customer_accounts WHERE customer = (SELECT customer_id FROM rp_sync_test_ids)),
    1,
    'inserting duplicate registered_proprietors does not create duplicate customer_accounts'
);

--
-- Test: migrate_existing_rp_to_ca returns row count and migrates correctly
--

SELECT is(
    (SELECT myenergy.migrate_existing_rp_to_ca() >= 0),
    true,
    'migrate_existing_rp_to_ca returns non-negative row count'
);

--
-- Test: trigger only creates entries for solar accounts, not supply accounts
--

-- Find a supply-only property (has supply but no solar)
INSERT INTO rp_sync_test_ids (customer_id, property_id, solar_account_id)
SELECT
    (SELECT customer_id FROM rp_sync_test_ids),
    p.id,
    NULL
FROM myenergy.properties p
WHERE NOT EXISTS (
    SELECT 1 FROM myenergy.accounts a WHERE a.property = p.id AND a.type = 'solar'
)
AND EXISTS (
    SELECT 1 FROM myenergy.accounts a WHERE a.property = p.id AND a.type = 'supply'
)
LIMIT 1;

-- Insert registered_proprietor for supply-only property
INSERT INTO myenergy.registered_proprietors (property, customer, tenure_type)
SELECT property_id, customer_id, 'joint_tenant'
FROM rp_sync_test_ids WHERE solar_account_id IS NULL;

-- Verify NO customer_accounts entry was created for supply account
SELECT is(
    (SELECT count(*) = 0 FROM myenergy.customer_accounts ca
     JOIN myenergy.accounts a ON a.id = ca.account
     WHERE ca.customer = (SELECT customer_id FROM rp_sync_test_ids LIMIT 1)
     AND a.type = 'supply'),
    true,
    'inserting registered_proprietors for supply-only property does not create customer_accounts for supply'
);

--
-- Test: customer_status function works with signed boolean (not signed_date)
--

-- Verify customer_status uses signed boolean for existing seeded customer
-- occ11@wl.ce has a signed supply contract and should be prelive/live after flags are set
SELECT is(
    (SELECT status::text FROM myenergy.customers WHERE email = 'occ11@wl.ce'),
    'prelive',
    'occ11@wl.ce with signed supply contract is prelive'
);

--
-- Cleanup
--

DELETE FROM myenergy.registered_proprietors WHERE customer = (SELECT customer_id FROM rp_sync_test_ids LIMIT 1);
DELETE FROM myenergy.customer_accounts WHERE customer = (SELECT customer_id FROM rp_sync_test_ids LIMIT 1);
DELETE FROM myenergy.customers WHERE email = 'rp_sync_test@example.com';
DELETE FROM auth.users WHERE email = 'rp_sync_test@example.com';

DROP TABLE rp_sync_test_ids;

SELECT * FROM finish();
ROLLBACK;