-- CI bootstrap: stubs the infrastructure that supabase-host normally provisions.
-- Run this once after the DB is up, before sqitch deploy.

-- Roles
CREATE ROLE supabase_admin WITH NOINHERIT CREATEROLE;
CREATE ROLE authenticator  WITH LOGIN NOINHERIT PASSWORD 'authenticator';
CREATE ROLE anon           WITH NOLOGIN NOINHERIT;
CREATE ROLE authenticated  WITH NOLOGIN NOINHERIT;
CREATE ROLE service_role   WITH NOLOGIN NOINHERIT BYPASSRLS;
CREATE ROLE supabase_auth_admin WITH NOINHERIT CREATEROLE;
CREATE ROLE grafanareader  WITH NOLOGIN;
CREATE ROLE tableau        WITH NOLOGIN;
CREATE ROLE flows          WITH NOLOGIN;

-- PostgREST role hierarchy
GRANT anon              TO authenticator;
GRANT authenticated     TO authenticator;
GRANT service_role      TO authenticator;
GRANT supabase_admin    TO tsdbadmin;
GRANT supabase_auth_admin TO tsdbadmin;

-- Extensions schema (supabase-host puts shared extensions here)
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgtap       WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA extensions TO PUBLIC;

-- Auth schema
CREATE SCHEMA IF NOT EXISTS auth;

-- Supabase auth helper functions (used in RLS policies and migrations)
CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claim.email', true),
    (current_setting('request.jwt.claims', true)::jsonb ->> 'email')
  )
$$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claim.sub', true),
    (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')
  )::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claim.role', true),
    (current_setting('request.jwt.claims', true)::jsonb ->> 'role')
  )
$$;

-- auth.users: full Supabase schema (columns referenced by migrations and seed)
CREATE TABLE IF NOT EXISTS auth.users (
    instance_id                uuid,
    id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aud                        text,
    role                       text,
    email                      text UNIQUE,
    encrypted_password         text,
    email_confirmed_at         timestamptz,
    invited_at                 timestamptz,
    confirmation_token         text DEFAULT '',
    confirmation_sent_at       timestamptz,
    recovery_token             text DEFAULT '',
    recovery_sent_at           timestamptz,
    email_change_token_new     text DEFAULT '',
    email_change               text DEFAULT '',
    email_change_sent_at       timestamptz,
    last_sign_in_at            timestamptz,
    raw_app_meta_data          jsonb,
    raw_user_meta_data         jsonb,
    is_super_admin             boolean,
    created_at                 timestamptz DEFAULT now(),
    updated_at                 timestamptz DEFAULT now(),
    phone                      text UNIQUE DEFAULT NULL,
    phone_confirmed_at         timestamptz,
    phone_change               text DEFAULT '',
    phone_change_token         text DEFAULT '',
    phone_change_sent_at       timestamptz,
    email_change_token_current text DEFAULT '',
    email_change_confirm_status smallint DEFAULT 0,
    banned_until               timestamptz,
    reauthentication_token     text DEFAULT '',
    reauthentication_sent_at   timestamptz,
    is_sso_user                boolean NOT NULL DEFAULT false,
    deleted_at                 timestamptz
);

-- auth.identities: referenced by create_user function
CREATE TABLE IF NOT EXISTS auth.identities (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    identity_data jsonb,
    provider      text,
    last_sign_in_at timestamptz,
    created_at    timestamptz DEFAULT now(),
    updated_at    timestamptz DEFAULT now()
);

GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticated, anon, service_role;
GRANT ALL   ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT SELECT ON auth.users TO authenticated, anon, service_role;

-- Postgraphile session helpers (from supabase-host 0011_auth_postgraphile_support)
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;
ALTER FUNCTION auth.jwt() OWNER TO supabase_auth_admin;

CREATE OR REPLACE FUNCTION auth.session_email() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    auth.email(),
    nullif(current_setting('jwt.claims.email', true), '')::text,
    (nullif(current_setting('jwt.claims', true), '')::jsonb ->> 'email')::text
  )
$$;
ALTER FUNCTION auth.session_email() OWNER TO supabase_auth_admin;
GRANT ALL ON FUNCTION auth.session_email() TO supabase_auth_admin;

CREATE OR REPLACE FUNCTION auth.session_role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    auth.role(),
    nullif(current_setting('jwt.claims.role', true), '')::text,
    (nullif(current_setting('jwt.claims', true), '')::jsonb ->> 'role')::text
  )
$$;
ALTER FUNCTION auth.session_role() OWNER TO supabase_auth_admin;
GRANT ALL ON FUNCTION auth.session_role() TO supabase_auth_admin;

CREATE OR REPLACE FUNCTION auth.session_jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    auth.jwt(),
    nullif(current_setting('jwt.claims', true), '')::jsonb
  )::jsonb
$$;
ALTER FUNCTION auth.session_jwt() OWNER TO supabase_auth_admin;
GRANT ALL ON FUNCTION auth.session_jwt() TO supabase_auth_admin;
