-- Revert supabase:0019_shared_ownership from pg

BEGIN;

-- Add back properties.owner column
ALTER TABLE myenergy.properties ADD COLUMN owner uuid;

-- Drop tables
DROP TABLE IF EXISTS myenergy.registered_proprietors;
DROP TABLE IF EXISTS myenergy.customer_corporate_bodies;
DROP TABLE IF EXISTS myenergy.corporate_bodies;

COMMIT;
