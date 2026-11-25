-- Verify supabase:0032_contract_signers_multi_party on pg

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'myenergy'
          AND p.proname = 'contract_signer_status'
          AND p.prosecdef
    ) THEN
        RAISE EXCEPTION 'myenergy.contract_signer_status(uuid) SECURITY DEFINER is missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'myenergy'
          AND p.proname = 'update_contract_signed_status'
          AND p.prosrc ILIKE '%LIMIT 1%'
    ) THEN
        RAISE EXCEPTION 'myenergy.update_contract_signed_status() still recomputes a single customer';
    END IF;

    IF (SELECT provolatile FROM pg_proc
        WHERE oid = 'myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum)'::regprocedure) <> 's' THEN
        RAISE EXCEPTION 'myenergy.customer_status() is not STABLE';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'myenergy'
          AND p.proname = 'contracts_sse_notify'
          AND p.prosrc LIKE '%signatures_required%'
    ) THEN
        RAISE EXCEPTION 'myenergy.contracts_sse_notify() payload is missing signatures_required';
    END IF;
END $$;

ROLLBACK;
