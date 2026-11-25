-- Revert supabase:0032_contract_signers_multi_party from pg
-- Restore the 0022 update_contract_signed_status() and 0025 contracts_sse_notify()
-- bodies, mark customer_status() IMMUTABLE again, and drop
-- contract_signer_status().

BEGIN;

DROP FUNCTION IF EXISTS myenergy.contract_signer_status(uuid);

ALTER FUNCTION myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum) IMMUTABLE;

CREATE OR REPLACE FUNCTION myenergy.contracts_sse_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.signed IS DISTINCT FROM OLD.signed AND NEW.signed = true THEN
        PERFORM pg_notify(
            'contract_signed',
            json_build_object('id', NEW.id)::text
        );
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION myenergy.update_contract_signed_status()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    sig_count integer;
    req_count integer;
    customer_id uuid;
    customer_row myenergy.customers;
    new_status myenergy.customer_status_enum;
BEGIN
    SELECT COUNT(*) INTO sig_count
    FROM myenergy.contract_signatures
    WHERE contract = COALESCE(NEW.contract, OLD.contract);

    SELECT signatures_required INTO req_count
    FROM myenergy.contracts
    WHERE id = COALESCE(NEW.contract, OLD.contract);

    UPDATE myenergy.contracts
    SET signed = (sig_count >= req_count)
    WHERE id = COALESCE(NEW.contract, OLD.contract);

    IF sig_count >= req_count THEN
        SELECT customer INTO customer_id
        FROM myenergy.customer_accounts
        WHERE account = ANY(
            SELECT id FROM myenergy.accounts WHERE current_contract = COALESCE(NEW.contract, OLD.contract)
        )
        LIMIT 1;

        IF customer_id IS NOT NULL THEN
            SELECT * INTO customer_row FROM myenergy.customers WHERE id = customer_id;
            SELECT myenergy.customer_status(customer_row) INTO new_status;
            UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

COMMIT;
