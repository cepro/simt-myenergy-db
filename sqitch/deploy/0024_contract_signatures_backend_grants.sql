-- Deploy supabase:0024_contract_signatures_backend_grants to pg
-- Grant public_backend the table-level permissions it needs on tables added
-- after the original 0000_initial.sql role grants.
--
-- Default privileges in 0003_postgraphile.sql only grant to the postgraphile
-- role, but PostGraphile runs the actual mutation as the role named in the
-- JWT (public_backend for the accountservice backend user). postgraphile has
-- been GRANTED public_backend, but that does not propagate table-level
-- privileges the other way - so any new table that needs to be readable or
-- mutable through GraphQL must also be explicitly GRANTed to public_backend.
-- RLS policies on the new tables include `TO public_backend` already; this
-- migration supplies the missing table-level GRANT.

BEGIN;

-- contract_signatures is INSERTed by the accountservice DocuSeal webhook
-- (see AccountsServiceImpl#contractSignatureAdd -> createContractSignature).
-- It also needs SELECT/UPDATE/DELETE for parity with the RLS policies
-- defined in 0022_contract_signatures.sql.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE myenergy.contract_signatures TO public_backend;

-- corporate_bodies, customer_corporate_bodies and registered_proprietors are
-- reference data managed by the admin add_property function (which runs as
-- tsdbadmin). They are SELECTed by GraphQL through public_backend; the only
-- RLS policy on each is FOR SELECT, so a SELECT grant is sufficient.
GRANT SELECT ON TABLE myenergy.corporate_bodies       TO public_backend;
GRANT SELECT ON TABLE myenergy.customer_corporate_bodies TO public_backend;
GRANT SELECT ON TABLE myenergy.registered_proprietors TO public_backend;

COMMIT;
