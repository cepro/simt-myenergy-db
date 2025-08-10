-- Deploy supabase:0003_postgraphile to pg

BEGIN;

-- PostGraphile setup for JWT authentication
-- This file creates the necessary types and users for PostGraphile integration

-- Create composite type for JWT token header
CREATE TYPE myenergy.jwt_header AS (
  typ text,
  alg text
);

-- Create composite type for app_metadata
CREATE TYPE myenergy.app_metadata AS (
  cepro_user boolean
);

-- Create composite type for JWT token claims
CREATE TYPE myenergy.jwt_claims AS (
  app_metadata myenergy.app_metadata,
  exp integer,
  iat integer,
  iss text,
  role text,
  sub uuid
);

-- Create composite type for complete JWT token structure
CREATE TYPE myenergy.jwt_token AS (
  header myenergy.jwt_header,
  claims myenergy.jwt_claims
);

-- Create postgraphile user
CREATE USER postgraphile WITH PASSWORD :'postgraphile_password';

-- Grant the public_backend role to postgraphile user
GRANT public_backend TO postgraphile;

-- Grant necessary permissions for postgraphile to function
GRANT USAGE ON SCHEMA myenergy TO postgraphile;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA myenergy TO postgraphile;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA myenergy TO postgraphile;

-- Grant permissions on future tables and sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA myenergy GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO postgraphile;
ALTER DEFAULT PRIVILEGES IN SCHEMA myenergy GRANT USAGE, SELECT ON SEQUENCES TO postgraphile;

-- Allow postgraphile to create temporary tables (needed for some PostGraphile features)
GRANT TEMPORARY ON DATABASE tsdb TO postgraphile;

COMMENT ON TYPE myenergy.jwt_token IS 'Complete JWT token structure with header and claims';
COMMENT ON TYPE myenergy.jwt_claims IS 'JWT token claims containing user authentication information';
COMMENT ON TYPE myenergy.jwt_header IS 'JWT token header with type and algorithm';
COMMENT ON TYPE myenergy.app_metadata IS 'Application-specific metadata for JWT tokens';

-- postgraphile 'smart comments'

COMMENT ON FUNCTION "myenergy"."customer"() IS '@name customerFn';
COMMENT ON FUNCTION "myenergy"."delete_customer"(text) IS '@name deleteCustomerFn';
COMMENT ON FUNCTION "myenergy"."delete_property"(uuid) IS '@name deletePropertyFn';


COMMIT;
