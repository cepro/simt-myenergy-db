-- reset-contract-signatures.sql
--
-- Roll back myenergy.contracts and signature tables to the state produced by
-- sqitch/seed/seed.sql. Idempotent: re-running is a no-op once the DB is in
-- seed state.
--
-- Seed invariants restored:
--   * contract_signatures: 8 rows for occ11@wl.ce, occ13@wl.ce, own11_13@wl.ce
--     on their current supply+solar contracts (signed_date = '2024-01-01').
--   * contract_signing_submitters: 0 rows (seed never inserts).
--   * contracts.signed: true for the seed-signed set above; false elsewhere.
--   * contracts.docuseal_submission_id, signed_contract_url, audit_log_url: NULL.
--
-- Tables NOT touched: customers, customer_events, accounts, properties,
-- payments, auth.users, etc. For a full stack reset, use the
-- simtricity-recreate-stack skill instead.

BEGIN;

-- 1. Delete non-seed contract_signatures.
-- A row is "seed-signed" iff: customer.email in (occ11@wl.ce, occ13@wl.ce,
-- own11_13@wl.ce) AND the contract is bound to that customer's account AND
-- contract.type IN ('supply', 'solar'). Anything else is post-seed drift.
-- The trigger contract_signatures_update_signed fires per row and sets
-- contracts.signed=false for any contract whose signatures we just removed.
DO $$
DECLARE
    v_deleted integer;
BEGIN
    DELETE FROM myenergy.contract_signatures cs
    USING myenergy.customers c
    WHERE cs.customer = c.id
      AND (
          c.email NOT IN ('occ11@wl.ce', 'occ13@wl.ce', 'own11_13@wl.ce')
          OR NOT EXISTS (
              SELECT 1 FROM myenergy.accounts a
              JOIN myenergy.customer_accounts ca ON ca.account = a.id
              WHERE a.current_contract = cs.contract
                AND ca.customer = cs.customer
          )
          OR NOT EXISTS (
              SELECT 1 FROM myenergy.contracts c2
              WHERE c2.id = cs.contract
                AND c2.type IN ('supply', 'solar')
          )
      );
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RAISE NOTICE 'reset-contract-signatures: deleted % contract_signatures row(s)', v_deleted;
END $$;

-- 2. Delete all contract_signing_submitters (seed creates 0).
DO $$
DECLARE
    v_deleted integer;
BEGIN
    DELETE FROM myenergy.contract_signing_submitters;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RAISE NOTICE 'reset-contract-signatures: deleted % contract_signing_submitters row(s)', v_deleted;
END $$;

-- 3. Clear DocuSeal metadata on contracts (seed leaves these NULL).
DO $$
DECLARE
    v_cleared integer;
BEGIN
    UPDATE myenergy.contracts
       SET docuseal_submission_id = NULL,
           signed_contract_url   = NULL,
           audit_log_url         = NULL
     WHERE docuseal_submission_id IS NOT NULL
        OR signed_contract_url   IS NOT NULL
        OR audit_log_url         IS NOT NULL;
    GET DIAGNOSTICS v_cleared = ROW_COUNT;
    RAISE NOTICE 'reset-contract-signatures: cleared DocuSeal metadata on % contract(s)', v_cleared;
END $$;

-- 4. Belt-and-braces: ensure contracts.signed is consistent with seed state.
-- The trigger from step 1 handles DELETE-driven changes. This catches drift
-- caused by direct UPDATEs that bypassed the trigger (e.g. signed=true set
-- without a corresponding contract_signatures row).
DO $$
DECLARE
    v_unsigned integer;
BEGIN
    UPDATE myenergy.contracts c
       SET signed = false
     WHERE c.signed = true
       AND NOT EXISTS (
           SELECT 1 FROM myenergy.accounts a
           JOIN myenergy.customer_accounts ca ON ca.account = a.id
           JOIN myenergy.customers          cust ON cust.id = ca.customer
           WHERE a.current_contract = c.id
             AND cust.email IN ('occ11@wl.ce', 'occ13@wl.ce', 'own11_13@wl.ce')
             AND c.type IN ('supply', 'solar')
       );
    GET DIAGNOSTICS v_unsigned = ROW_COUNT;
    RAISE NOTICE 'reset-contract-signatures: set signed=false on % contract(s)', v_unsigned;
END $$;

COMMIT;