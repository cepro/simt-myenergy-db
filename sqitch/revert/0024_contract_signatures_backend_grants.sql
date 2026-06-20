-- Revert supabase:0024_contract_signatures_backend_grants from pg

BEGIN;

REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLE myenergy.contract_signatures FROM public_backend;
REVOKE SELECT ON TABLE myenergy.corporate_bodies        FROM public_backend;
REVOKE SELECT ON TABLE myenergy.customer_corporate_bodies FROM public_backend;
REVOKE SELECT ON TABLE myenergy.registered_proprietors  FROM public_backend;

COMMIT;
