-- Verify supabase:0021_corporate_bodies_grants on pg

BEGIN;

-- Check that RLS is enabled on registered_proprietors
SELECT 1 FROM pg_tables
WHERE schemaname = 'myenergy'
  AND tablename = 'registered_proprietors'
  AND rowsecurity = true;

-- Check that the policy exists
SELECT 1 FROM pg_policies
WHERE schemaname = 'myenergy'
  AND tablename = 'registered_proprietors'
  AND policyname = 'Customers can view their registered proprietors or all if cepro user';

-- Check RLS is enabled on corporate_bodies
SELECT 1 FROM pg_tables
WHERE schemaname = 'myenergy'
  AND tablename = 'corporate_bodies'
  AND rowsecurity = true;

SELECT 1 FROM pg_policies
WHERE schemaname = 'myenergy'
  AND tablename = 'corporate_bodies'
  AND policyname = 'Customers can view their corporate bodies or all if cepro user';

-- Check RLS is enabled on customer_corporate_bodies
SELECT 1 FROM pg_tables
WHERE schemaname = 'myenergy'
  AND tablename = 'customer_corporate_bodies'
  AND rowsecurity = true;

SELECT 1 FROM pg_policies
WHERE schemaname = 'myenergy'
  AND tablename = 'customer_corporate_bodies'
  AND policyname = 'Customers can view their corporate body memberships or all if cepro user';

-- Check corporate_bodies timestamps and trigger
SELECT 1 FROM pg_columns
WHERE schemaname = 'myenergy'
  AND tablename = 'corporate_bodies'
  AND attname = 'created_at';
SELECT 1 FROM pg_columns
WHERE schemaname = 'myenergy'
  AND tablename = 'corporate_bodies'
  AND attname = 'updated_at';
SELECT 1 FROM pg_trigger
WHERE tgname = 'corporate_bodies_updated_at';

-- Check customer_corporate_bodies timestamps and trigger
SELECT 1 FROM pg_columns
WHERE schemaname = 'myenergy'
  AND tablename = 'customer_corporate_bodies'
  AND attname = 'created_at';
SELECT 1 FROM pg_columns
WHERE schemaname = 'myenergy'
  AND tablename = 'customer_corporate_bodies'
  AND attname = 'updated_at';
SELECT 1 FROM pg_trigger
WHERE tgname = 'customer_corporate_bodies_updated_at';

-- Check registered_proprietors timestamps and trigger
SELECT 1 FROM pg_columns
WHERE schemaname = 'myenergy'
  AND tablename = 'registered_proprietors'
  AND attname = 'created_at';
SELECT 1 FROM pg_columns
WHERE schemaname = 'myenergy'
  AND tablename = 'registered_proprietors'
  AND attname = 'updated_at';
SELECT 1 FROM pg_trigger
WHERE tgname = 'registered_proprietors_updated_at';

ROLLBACK;