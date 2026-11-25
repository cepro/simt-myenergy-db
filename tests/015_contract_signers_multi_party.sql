-- Multi-party DocuSeal signing: schema from 0026 and behaviour from 0032.
--
-- Fixture (sqitch/seed/seed.sql): HMCE Plot-17 solar account bound to contract
-- 00d21c76-...252e0 (multi-party terms ...c31f98, signatures_required = 2), with
-- co-proprietors multi17a@hm.ce and multi17b@hm.ce as owners.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, extensions, public;

SELECT extensions.plan(35);

SELECT is((SELECT current_role), 'tsdbadmin', 'initial role');

--
-- 0026: contract_terms.is_multi_party and contracts.audit_log_url
--

SELECT has_column('myenergy', 'contract_terms', 'is_multi_party', 'contract_terms has is_multi_party');
SELECT col_not_null('myenergy', 'contract_terms', 'is_multi_party', 'contract_terms.is_multi_party is NOT NULL');
SELECT col_default_is('myenergy', 'contract_terms', 'is_multi_party', 'false', 'contract_terms.is_multi_party defaults to false');
SELECT is(
    (SELECT is_multi_party FROM myenergy.contract_terms WHERE id = 'dcdb73f0-5ac1-438f-a91e-4c1d80e31f98'),
    true,
    'seeded HMCE multi-party solar terms have is_multi_party = true'
);
SELECT is(
    (SELECT is_multi_party FROM myenergy.contract_terms WHERE id = 'dcdb73f0-5ac1-438f-a91e-4c1d80e31f97'),
    false,
    'seeded HMCE single-signer solar terms have is_multi_party = false'
);
SELECT has_column('myenergy', 'contracts', 'audit_log_url', 'contracts has audit_log_url');

--
-- 0026: contract_signing_submitters structure, constraints, RLS and grants
--

SELECT has_table('myenergy', 'contract_signing_submitters', 'contract_signing_submitters exists');
SELECT columns_are('myenergy', 'contract_signing_submitters',
    ARRAY['contract', 'customer', 'slug', 'role', 'created_at'],
    'contract_signing_submitters has the expected columns');
SELECT col_is_pk('myenergy', 'contract_signing_submitters', ARRAY['contract', 'customer'],
    'contract_signing_submitters PK is (contract, customer)');
SELECT fk_ok('myenergy', 'contract_signing_submitters', 'contract', 'myenergy', 'contracts', 'id',
    'contract_signing_submitters.contract references contracts');
SELECT fk_ok('myenergy', 'contract_signing_submitters', 'customer', 'myenergy', 'customers', 'id',
    'contract_signing_submitters.customer references customers');

SELECT throws_ok(
    $$INSERT INTO myenergy.contract_signing_submitters (contract, customer, slug, role)
      SELECT '00d21c76-2566-4021-8192-28d509c252e0', id, 'slug-x', 'Third Party'
      FROM myenergy.customers WHERE email = 'multi17a@hm.ce'$$,
    '23514',
    NULL,
    'role must be First Party or Second Party'
);

SELECT is(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'myenergy.contract_signing_submitters'::regclass),
    true,
    'RLS is enabled on contract_signing_submitters'
);
SELECT policies_are('myenergy', 'contract_signing_submitters', ARRAY[
    'Customers can view their own signing submitter',
    'Backend can insert signing submitters',
    'Backend can delete signing submitters'
], 'contract_signing_submitters policies');
SELECT table_privs_are('myenergy', 'contract_signing_submitters', 'public_backend',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
    'public_backend can read and write contract_signing_submitters');

-- Fixture rows: what AccountsServiceImpl#createOrGetMultiSubmitterSubmission writes.
INSERT INTO myenergy.contract_signing_submitters (contract, customer, slug, role)
SELECT '00d21c76-2566-4021-8192-28d509c252e0', id,
       CASE email WHEN 'multi17a@hm.ce' THEN 'slug-a' ELSE 'slug-b' END,
       CASE email WHEN 'multi17a@hm.ce' THEN 'First Party' ELSE 'Second Party' END
FROM myenergy.customers WHERE email IN ('multi17a@hm.ce', 'multi17b@hm.ce');

SELECT throws_ok(
    $$INSERT INTO myenergy.contract_signing_submitters (contract, customer, slug, role)
      SELECT '00d21c76-2566-4021-8192-28d509c252e0', id, 'slug-dup', 'First Party'
      FROM myenergy.customers WHERE email = 'multi17a@hm.ce'$$,
    '23505',
    NULL,
    'one submitter row per (contract, customer)'
);

-- Customers have no table grant on contract_signing_submitters (only the
-- backend reads it), so signer state reaches the app via contract_signer_status().
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.email', 'multi17a@hm.ce', true);
SELECT throws_ok(
    $$SELECT * FROM myenergy.contract_signing_submitters$$,
    '42501',
    NULL,
    'authenticated cannot read contract_signing_submitters directly'
);
SELECT set_config('request.jwt.claim.email', NULL, true);
RESET ROLE;

--
-- 0032: contract_signer_status() before anyone signs
--

SELECT is(
    (SELECT prosecdef FROM pg_proc WHERE oid = 'myenergy.contract_signer_status(uuid)'::regprocedure),
    true,
    'contract_signer_status is SECURITY DEFINER'
);
SELECT ok(
    NOT has_function_privilege('anon', 'myenergy.contract_signer_status(uuid)', 'EXECUTE'),
    'anon cannot execute contract_signer_status'
);
SELECT volatility_is('myenergy', 'customer_status',
    ARRAY['myenergy.customers', 'myenergy.customer_status_enum'], 'stable',
    'customer_status is STABLE (it reads tables)');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.email', 'multi17a@hm.ce', true);
SELECT results_eq(
    $$SELECT s.fullname, s.role, s.signed, s.is_current_customer
      FROM myenergy.contract_signer_status('00d21c76-2566-4021-8192-28d509c252e0') s$$,
    $$VALUES ('HMCE 17 Multi A'::text, 'First Party'::text, false, true),
             ('HMCE 17 Multi B'::text, 'Second Party'::text, false, false)$$,
    'signer status as proprietor A: both signers listed, nobody signed, A is current'
);
SELECT set_config('request.jwt.claim.email', NULL, true);
RESET ROLE;

--
-- 0032: first signature, contract not yet signed
--

-- Clear the payment/details gates so the contract signature is the last
-- thing between both proprietors and 'live'.
UPDATE myenergy.customers
   SET has_payment_method = true, confirmed_details_at = now(), allow_onboard_transition = true
 WHERE email IN ('multi17a@hm.ce', 'multi17b@hm.ce');

SELECT results_eq(
    $$SELECT status::text FROM myenergy.customers WHERE email IN ('multi17a@hm.ce', 'multi17b@hm.ce') ORDER BY email$$,
    $$VALUES ('onboarding'::text), ('onboarding'::text)$$,
    'both proprietors onboarding before signing'
);

INSERT INTO myenergy.contract_signatures (contract, customer, signed_date)
SELECT '00d21c76-2566-4021-8192-28d509c252e0', id, '2026-11-01'
FROM myenergy.customers WHERE email = 'multi17b@hm.ce';

SELECT is(
    (SELECT signed FROM myenergy.contracts WHERE id = '00d21c76-2566-4021-8192-28d509c252e0'),
    false,
    'multi-party contract stays unsigned at 1 of 2 signatures'
);

-- Customers can't read contract_signatures directly either.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.email', 'multi17a@hm.ce', true);
SELECT throws_ok(
    $$SELECT * FROM myenergy.contract_signatures$$,
    '42501',
    NULL,
    'authenticated cannot read contract_signatures directly'
);
SELECT results_eq(
    $$SELECT s.fullname, s.signed, s.signed_date
      FROM myenergy.contract_signer_status('00d21c76-2566-4021-8192-28d509c252e0') s$$,
    $$VALUES ('HMCE 17 Multi A'::text, false, NULL::date),
             ('HMCE 17 Multi B'::text, true, '2026-11-01'::date)$$,
    'signer status as proprietor A shows B has signed and A has not'
);

-- An unrelated customer gets nothing.
SELECT set_config('request.jwt.claim.email', 'occ11@wl.ce', true);
SELECT is(
    (SELECT count(*)::int FROM myenergy.contract_signer_status('00d21c76-2566-4021-8192-28d509c252e0')),
    0,
    'signer status is empty for a customer not on the contract'
);

-- The backend (JWT role claim) sees every signer.
SELECT set_config('request.jwt.claim.email', NULL, true);
SELECT set_config('request.jwt.claim.role', 'public_backend', true);
SELECT results_eq(
    $$SELECT s.role, s.signed, s.is_current_customer
      FROM myenergy.contract_signer_status('00d21c76-2566-4021-8192-28d509c252e0') s$$,
    $$VALUES ('First Party'::text, false, false),
             ('Second Party'::text, true, false)$$,
    'signer status as backend lists both signers'
);
SELECT set_config('request.jwt.claim.role', NULL, true);
RESET ROLE;

--
-- 0032: second signature flips signed and recomputes BOTH proprietors' status
--

INSERT INTO myenergy.contract_signatures (contract, customer, signed_date)
SELECT '00d21c76-2566-4021-8192-28d509c252e0', id, '2026-11-02'
FROM myenergy.customers WHERE email = 'multi17a@hm.ce';

SELECT is(
    (SELECT signed FROM myenergy.contracts WHERE id = '00d21c76-2566-4021-8192-28d509c252e0'),
    true,
    'multi-party contract signed at 2 of 2 signatures'
);
SELECT is(
    (SELECT status::text FROM myenergy.customers WHERE email = 'multi17a@hm.ce'),
    'live',
    'proprietor A status recomputed to live'
);
SELECT is(
    (SELECT status::text FROM myenergy.customers WHERE email = 'multi17b@hm.ce'),
    'live',
    'proprietor B status recomputed to live (was skipped by the old LIMIT 1)'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.email', 'multi17b@hm.ce', true);
SELECT results_eq(
    $$SELECT s.signed, s.is_current_customer
      FROM myenergy.contract_signer_status('00d21c76-2566-4021-8192-28d509c252e0') s$$,
    $$VALUES (true, false), (true, true)$$,
    'signer status as proprietor B: both signed, B is current'
);
SELECT set_config('request.jwt.claim.email', NULL, true);
RESET ROLE;

--
-- 0032: contract_signed NOTIFY payload
--

SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE oid = 'myenergy.contracts_sse_notify()'::regprocedure),
    '''signatures_required'', NEW\.signatures_required',
    'contract_signed payload includes signatures_required'
);
SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE oid = 'myenergy.contracts_sse_notify()'::regprocedure),
    '''signed'', NEW\.signed',
    'contract_signed payload includes signed'
);

--
-- Removing a signature unsigns the contract again
--

DELETE FROM myenergy.contract_signatures
 WHERE contract = '00d21c76-2566-4021-8192-28d509c252e0'
   AND customer = (SELECT id FROM myenergy.customers WHERE email = 'multi17a@hm.ce');

SELECT is(
    (SELECT signed FROM myenergy.contracts WHERE id = '00d21c76-2566-4021-8192-28d509c252e0'),
    false,
    'multi-party contract unsigned again after a signature is removed'
);

SELECT * FROM finish();
ROLLBACK;
