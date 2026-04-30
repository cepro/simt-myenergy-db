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

-- auth.users: columns referenced by migrations (INSERT, SELECT, triggers)
CREATE TABLE IF NOT EXISTS auth.users (
    instance_id          uuid,
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aud                  text,
    role                 text,
    email                text UNIQUE,
    phone                text,
    encrypted_password   text,
    email_confirmed_at   timestamptz,
    recovery_sent_at     timestamptz,
    last_sign_in_at      timestamptz,
    raw_app_meta_data    jsonb,
    raw_user_meta_data   jsonb,
    created_at           timestamptz DEFAULT now(),
    updated_at           timestamptz DEFAULT now(),
    confirmation_token   text DEFAULT '',
    email_change         text DEFAULT '',
    email_change_token_new text DEFAULT '',
    recovery_token       text DEFAULT ''
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
