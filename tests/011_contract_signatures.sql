BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, extensions, public;

SELECT extensions.plan(17);

SELECT is((SELECT current_role), 'tsdbadmin', 'initial role');

--
-- Test contract_signatures table structure
--

SELECT is(
    (SELECT count(*) = 3 FROM information_schema.columns
     WHERE table_name = 'contract_signatures'
     AND column_name IN ('contract', 'customer', 'signed_date')),
    true,
    'contract_signatures has contract, customer, signed_date columns'
);

SELECT is(
    (SELECT contype FROM pg_constraint WHERE conrelid = 'contract_signatures'::regclass AND conname = 'contract_signatures_pkey'),
    'p',
    'contract_signatures has primary key on (contract, customer)'
);

--
-- Test contracts.signatures_required and signed columns
--

SELECT is(
    (SELECT count(*) = 1 FROM information_schema.columns
     WHERE table_name = 'contracts' AND column_name = 'signatures_required'),
    true,
    'contracts has signatures_required column'
);

SELECT is(
    (SELECT column_default FROM information_schema.columns
     WHERE table_name = 'contracts' AND column_name = 'signatures_required'),
    '1',
    'contracts.signatures_required defaults to 1'
);

SELECT is(
    (SELECT count(*) = 1 FROM information_schema.columns
     WHERE table_name = 'contracts' AND column_name = 'signed'),
    true,
    'contracts has signed column'
);

SELECT is(
    (SELECT column_default FROM information_schema.columns
     WHERE table_name = 'contracts' AND column_name = 'signed'),
    'false',
    'contracts.signed defaults to false'
);

--
-- Create test data: a contract with signatures_required = 2
--

CREATE TEMP TABLE test_contract_ids (contract_id uuid);

INSERT INTO test_contract_ids (contract_id)
SELECT extensions.uuid_generate_v4();

INSERT INTO myenergy.contracts (id, terms, type, signatures_required, signed)
SELECT contract_id, 'c95dd1d5-b1fd-4db2-9570-7dca975a9349'::uuid, 'supply', 2, false
FROM test_contract_ids;

PREPARE get_test_contract_id AS SELECT contract_id FROM test_contract_ids;

--
-- Test: signed=false when signatures < signatures_required
--

INSERT INTO myenergy.contract_signatures (contract, customer, signed_date)
SELECT (SELECT contract_id FROM test_contract_ids), (SELECT id FROM myenergy.customers WHERE email = 'occ11@wl.ce'), current_date
ON CONFLICT DO NOTHING;

SELECT is(
    (SELECT signed FROM myenergy.contracts WHERE id = (SELECT contract_id FROM test_contract_ids)),
    false,
    'contract signed=false when 1 of 2 signatures collected'
);

--
-- Test: adding second signature triggers signed=true
--

INSERT INTO myenergy.contract_signatures (contract, customer, signed_date)
SELECT (SELECT contract_id FROM test_contract_ids), (SELECT id FROM myenergy.customers WHERE email = 'occ13@wl.ce'), current_date
ON CONFLICT DO NOTHING;

SELECT is(
    (SELECT signed FROM myenergy.contracts WHERE id = (SELECT contract_id FROM test_contract_ids)),
    true,
    'contract signed=true when 2 of 2 signatures collected'
);

--
-- Test: signature count decreases and signed flips back to false
--

DELETE FROM myenergy.contract_signatures
WHERE contract = (SELECT contract_id FROM test_contract_ids)
AND customer = (SELECT id FROM myenergy.customers WHERE email = 'occ13@wl.ce');

SELECT is(
    (SELECT signed FROM myenergy.contracts WHERE id = (SELECT contract_id FROM test_contract_ids)),
    false,
    'contract signed=false after removing signature'
);

--
-- Test: update_contract_signed_status trigger function exists
--

SELECT is(
    (SELECT count(*) > 0 FROM pg_proc WHERE proname = 'update_contract_signed_status'),
    true,
    'update_contract_signed_status function exists'
);

SELECT is(
    (SELECT count(*) > 0 FROM pg_trigger WHERE tgname = 'contract_signatures_update_signed'),
    true,
    'contract_signatures_update_signed trigger exists'
);

--
-- Test: RLS policies exist on contract_signatures
--

SELECT is(
    (SELECT count(*) >= 3 FROM pg_policies WHERE tablename = 'contract_signatures'),
    true,
    'contract_signatures has RLS policies'
);

--
-- Cleanup test contract
--

DELETE FROM myenergy.contract_signatures WHERE contract = (SELECT contract_id FROM test_contract_ids);
DELETE FROM myenergy.contracts WHERE id = (SELECT contract_id FROM test_contract_ids);

DROP TABLE test_contract_ids;

--
-- Test: existing signed contract can have contract_signatures entries
-- (seed data sets signed=true directly, but contract_signatures should be insertable)
--

-- Create a signed contract with signature for testing
INSERT INTO myenergy.contracts (id, terms, type, signatures_required, signed)
SELECT extensions.uuid_generate_v4(), 'c95dd1d5-b1fd-4db2-9570-7dca975a9349'::uuid, 'supply', 1, true;

INSERT INTO myenergy.contract_signatures (contract, customer, signed_date)
SELECT c.id, (SELECT id FROM myenergy.customers WHERE email = 'occ11@wl.ce'), current_date
FROM myenergy.contracts c WHERE c.signed = true AND c.signatures_required = 1
AND NOT EXISTS (SELECT 1 FROM myenergy.contract_signatures WHERE contract = c.id)
LIMIT 1;

SELECT is(
    (SELECT count(*) > 0 FROM myenergy.contract_signatures cs
     JOIN myenergy.contracts c ON c.id = cs.contract
     WHERE c.signed = true AND c.signatures_required = 1),
    true,
    'can create contract_signatures entries for signed contracts'
);

-- Cleanup - only delete contract_signatures, contracts are temp and will be rolled back
DELETE FROM myenergy.contract_signatures WHERE contract IN (
    SELECT id FROM myenergy.contracts WHERE signatures_required = 1 AND signed = true
    AND created_at = (SELECT MAX(created_at) FROM myenergy.contracts WHERE signatures_required = 1 AND signed = true)
);

-- Test: views use signed boolean instead of signed_date
--

SELECT is(
    (SELECT count(*) = 0 FROM information_schema.columns
     WHERE table_name = 'contracts' AND column_name = 'signed_date'),
    true,
    'contracts no longer has signed_date column'
);

SELECT is(
    (SELECT count(*) > 0 FROM pg_views WHERE viewname = 'property_supply_view'
     AND definition NOT LIKE '%signed_date%'),
    true,
    'property_supply_view does not reference signed_date'
);

SELECT is(
    (SELECT count(*) > 0 FROM pg_views WHERE viewname = 'property_solar_view'
     AND definition NOT LIKE '%signed_date%'),
    true,
    'property_solar_view does not reference signed_date'
);

SELECT * FROM finish();
ROLLBACK;