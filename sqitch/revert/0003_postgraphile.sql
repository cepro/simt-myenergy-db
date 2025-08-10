-- Revert supabase:0003_postgraphile from pg

BEGIN;

-- Grant current user the postgraphile role temporarily to drop owned objects
GRANT postgraphile TO CURRENT_USER;

-- Revoke role membership first
REVOKE public_backend FROM postgraphile;

-- Drop any objects owned by the user and revoke all privileges
DROP OWNED BY postgraphile CASCADE;
REVOKE ALL ON DATABASE tsdb FROM postgraphile;

-- Now drop the user
DROP USER postgraphile;

DROP TYPE myenergy.jwt_token;
DROP TYPE myenergy.jwt_claims;
DROP TYPE myenergy.app_metadata;
DROP TYPE myenergy.jwt_header;

COMMENT ON FUNCTION "myenergy"."customer"() IS null;
COMMENT ON FUNCTION "myenergy"."delete_customer"(text) IS null;
COMMENT ON FUNCTION "myenergy"."delete_property"(uuid) IS null;

COMMIT;
