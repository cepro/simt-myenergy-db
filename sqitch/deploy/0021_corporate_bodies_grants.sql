-- Deploy supabase:0021_corporate_bodies_grants to pg
-- Enable RLS on registered_proprietors and grant access similar to properties table

BEGIN;

-- Enable RLS on registered_proprietors
ALTER TABLE myenergy.registered_proprietors ENABLE ROW LEVEL SECURITY;

-- Read policy - mirrors properties table pattern
DROP POLICY IF EXISTS "Customers can view their registered proprietors or all if cepro user"
  ON myenergy.registered_proprietors;
CREATE POLICY "Customers can view their registered proprietors or all if cepro user"
  ON myenergy.registered_proprietors
  FOR SELECT
  TO authenticated, public_backend, grafanareader
  USING (
    myenergy.is_backend_user()
    OR (customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email()))
    OR (EXISTS (
      SELECT 1 FROM myenergy.customers
      WHERE email = auth.session_email() AND cepro_user = true
    ))
  );

-- Enable RLS on corporate_bodies
ALTER TABLE myenergy.corporate_bodies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their corporate bodies or all if cepro user"
  ON myenergy.corporate_bodies;
CREATE POLICY "Customers can view their corporate bodies or all if cepro user"
  ON myenergy.corporate_bodies
  FOR SELECT
  TO authenticated, public_backend, grafanareader
  USING (
    myenergy.is_backend_user()
    OR EXISTS (
      SELECT 1
      FROM myenergy.customer_corporate_bodies ccb
      JOIN myenergy.customers c ON c.id = ccb.customer
      WHERE ccb.corporate_body = corporate_bodies.id
        AND c.email = auth.session_email()
    )
    OR EXISTS (
      SELECT 1 FROM myenergy.customers
      WHERE email = auth.session_email() AND cepro_user = true
    )
  );

-- Enable RLS on customer_corporate_bodies
ALTER TABLE myenergy.customer_corporate_bodies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their corporate body memberships or all if cepro user"
  ON myenergy.customer_corporate_bodies;
CREATE POLICY "Customers can view their corporate body memberships or all if cepro user"
  ON myenergy.customer_corporate_bodies
  FOR SELECT
  TO authenticated, public_backend, grafanareader
  USING (
    myenergy.is_backend_user()
    OR (customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email()))
    OR EXISTS (
      SELECT 1 FROM myenergy.customers
      WHERE email = auth.session_email() AND cepro_user = true
    )
  );

COMMIT;
