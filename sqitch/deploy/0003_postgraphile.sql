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
  email text,
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


--
-- Update functions to use auth.session_* functions which support both 
-- Postgraphile GraphQL AND Supabase REST incoming requests. 
--

CREATE OR REPLACE FUNCTION myenergy.customer()
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    select id
    FROM myenergy.customers
    where email = auth.session_email();
$function$
;

CREATE OR REPLACE FUNCTION myenergy.is_backend_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT current_user = 'grafanareader' or (
        SELECT current_user = 'public_backend'
    ) or (
	    SELECT current_user = 'authenticated' and (select auth.session_role() = 'public_backend')
    );
$function$
;

DROP POLICY "Customers can read their own and property owners records" ON myenergy.customers;

CREATE POLICY "Customers can read their own and property owners records" 
ON myenergy.customers FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (email = auth.session_email()) 
    OR (id IN (SELECT myenergy.get_property_owners_for_auth_user(auth.session_email())))
);

DROP POLICY "Customers can view their own properties or all if cepro user" ON myenergy.properties;

CREATE POLICY "Customers can view their own properties or all if cepro user" 
ON myenergy.properties FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id = ANY (myenergy.properties_by_account())) 
    OR (id = ANY (myenergy.properties_owned())) 
    OR (EXISTS (SELECT 1 FROM myenergy.customers WHERE customers.email = auth.session_email() AND customers.cepro_user = true))
);

DROP POLICY "Users can see terms for escos they have accounts in or all if c" ON myenergy.contract_terms;

CREATE POLICY "Users can see terms for escos they have accounts in or all if c" 
ON myenergy.contract_terms FOR SELECT TO authenticated, public_backend, grafanareader 
USING (
    myenergy.is_backend_user() 
    OR (id IN (SELECT contract_terms_esco.terms FROM myenergy.contract_terms_esco)) 
    OR (EXISTS (SELECT 1 FROM myenergy.customers WHERE customers.email = auth.session_email() AND customers.cepro_user = true))
);



COMMIT;
