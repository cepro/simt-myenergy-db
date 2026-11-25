-- Deploy supabase:0032_contract_signers_multi_party to pg
--
-- Follow-up DB work for multi-party DocuSeal signing (0026). Three changes:
--
--   1. update_contract_signed_status() recomputes customers.status for EVERY
--      customer on the contract's accounts. The 0022 version picked one
--      customer with LIMIT 1, so on a two-proprietor contract the second
--      proprietor's status was never recomputed when the contract became signed.
--
--      customer_status() is also changed from IMMUTABLE to STABLE. It reads
--      contracts, accounts and auth.users, so IMMUTABLE was wrong: called from
--      this trigger it did not see the contracts.signed = true written a moment
--      earlier, and returned the pre-signing status. The recompute therefore
--      never took effect when the trigger itself flipped signed. Nothing
--      (index, generated column) depends on it being IMMUTABLE.
--
--   2. The contract_signed NOTIFY payload (0025) now carries signed and
--      signatures_required alongside id, so SSE consumers can use them
--      without a follow-up lookup. Still fires only on the false -> true edge.
--
--   3. New myenergy.contract_signer_status(contract_id) returns one row per
--      signer: who they are, their DocuSeal role, and whether and when they
--      signed. RLS on contract_signatures and contract_signing_submitters only
--      shows a customer their own row, so this is SECURITY DEFINER and does
--      its own access check (see the function comment).

BEGIN;

-- 1. Recompute status for every customer on the contract -------------------

ALTER FUNCTION myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum) STABLE;

CREATE OR REPLACE FUNCTION myenergy.update_contract_signed_status()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_contract uuid := COALESCE(NEW.contract, OLD.contract);
    sig_count integer;
    req_count integer;
    customer_id uuid;
    customer_row myenergy.customers;
    new_status myenergy.customer_status_enum;
BEGIN
    SELECT COUNT(*) INTO sig_count
    FROM myenergy.contract_signatures
    WHERE contract = v_contract;

    SELECT signatures_required INTO req_count
    FROM myenergy.contracts
    WHERE id = v_contract;

    UPDATE myenergy.contracts
    SET signed = (sig_count >= req_count)
    WHERE id = v_contract;

    IF sig_count >= req_count THEN
        FOR customer_id IN
            SELECT DISTINCT ca.customer
            FROM myenergy.customer_accounts ca
            JOIN myenergy.accounts a ON a.id = ca.account
            WHERE a.current_contract = v_contract
        LOOP
            SELECT * INTO customer_row FROM myenergy.customers WHERE id = customer_id;
            SELECT myenergy.customer_status(customer_row) INTO new_status;
            UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;
        END LOOP;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

ALTER FUNCTION myenergy.update_contract_signed_status() OWNER TO :"adminrole";

-- 2. Richer contract_signed NOTIFY payload ---------------------------------

CREATE OR REPLACE FUNCTION myenergy.contracts_sse_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Fire only on the false -> true edge (see 0025).
    IF NEW.signed IS DISTINCT FROM OLD.signed AND NEW.signed = true THEN
        PERFORM pg_notify(
            'contract_signed',
            json_build_object(
                'id', NEW.id,
                'signed', NEW.signed,
                'signatures_required', NEW.signatures_required
            )::text
        );
    END IF;
    RETURN NULL;
END;
$$;

-- 3. Per-contract signer status --------------------------------------------

CREATE FUNCTION myenergy.contract_signer_status(contract_id uuid)
RETURNS TABLE (
    customer uuid,
    fullname text,
    role text,
    signed boolean,
    signed_date date,
    is_current_customer boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_email text := auth.session_email();
    v_customer uuid;
    v_allowed boolean;
BEGIN
    SELECT c.id INTO v_customer
    FROM myenergy.customers c
    WHERE c.email = v_email;

    -- current_user is the function owner here, so is_backend_user() can't be
    -- used. Check the caller from the session instead: the backend JWT role
    -- claim (what is_backend_user() trusts for 'authenticated'), the login
    -- role, a cepro admin, or a customer on one of the contract's accounts.
    -- COALESCE throughout: auth.session_role() is NULL for ordinary customers,
    -- and a NULL here must mean "not allowed".
    v_allowed := COALESCE(
        auth.session_role() = 'public_backend'
        OR session_user IN ('public_backend', 'grafanareader')
        OR EXISTS (
            SELECT 1 FROM myenergy.customers c
            WHERE c.id = v_customer AND c.cepro_user = true
        )
        OR EXISTS (
            SELECT 1
            FROM myenergy.customer_accounts ca
            JOIN myenergy.accounts a ON a.id = ca.account
            WHERE a.current_contract = contract_signer_status.contract_id
              AND ca.customer = v_customer
        ),
        false);

    IF NOT v_allowed THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH signers AS (
        SELECT css.customer, css.role
        FROM myenergy.contract_signing_submitters css
        WHERE css.contract = contract_signer_status.contract_id
        UNION
        SELECT cs.customer, NULL::text
        FROM myenergy.contract_signatures cs
        WHERE cs.contract = contract_signer_status.contract_id
          AND NOT EXISTS (
              SELECT 1 FROM myenergy.contract_signing_submitters css
              WHERE css.contract = cs.contract AND css.customer = cs.customer
          )
    )
    SELECT s.customer,
           c.fullname,
           s.role,
           (cs.customer IS NOT NULL),
           cs.signed_date,
           (s.customer IS NOT DISTINCT FROM v_customer)
    FROM signers s
    JOIN myenergy.customers c ON c.id = s.customer
    LEFT JOIN myenergy.contract_signatures cs
           ON cs.contract = contract_signer_status.contract_id
          AND cs.customer = s.customer
    ORDER BY s.role NULLS LAST, s.customer;
END;
$$;

ALTER FUNCTION myenergy.contract_signer_status(uuid) OWNER TO :"adminrole";

COMMENT ON FUNCTION myenergy.contract_signer_status(uuid) IS
    'One row per signer of a contract: the proprietors in contract_signing_submitters '
    '(multi-party) plus anyone with a contract_signatures row. Signers on a multi-party '
    'contract appear once the DocuSeal submission has been created (first open of the '
    'embed). Returns rows only to the backend, cepro admins, and customers on one of '
    'the contract''s accounts; anyone else gets an empty result.';

REVOKE ALL ON FUNCTION myenergy.contract_signer_status(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION myenergy.contract_signer_status(uuid) TO authenticated, public_backend, grafanareader;

COMMIT;
