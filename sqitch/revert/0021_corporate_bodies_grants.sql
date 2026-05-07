-- Revert supabase:0021_corporate_bodies_grants from pg

BEGIN;

-- Drop policy and disable RLS on customer_corporate_bodies
DROP POLICY IF EXISTS "Customers can view their corporate body memberships or all if cepro user"
  ON myenergy.customer_corporate_bodies;
ALTER TABLE myenergy.customer_corporate_bodies DISABLE ROW LEVEL SECURITY;

-- Drop policy and disable RLS on corporate_bodies
DROP POLICY IF EXISTS "Customers can view their corporate bodies or all if cepro user"
  ON myenergy.corporate_bodies;
ALTER TABLE myenergy.corporate_bodies DISABLE ROW LEVEL SECURITY;

-- Drop policy and disable RLS on registered_proprietors
DROP POLICY IF EXISTS "Customers can view their registered proprietors or all if cepro user"
  ON myenergy.registered_proprietors;
ALTER TABLE myenergy.registered_proprietors DISABLE ROW LEVEL SECURITY;

COMMIT;
