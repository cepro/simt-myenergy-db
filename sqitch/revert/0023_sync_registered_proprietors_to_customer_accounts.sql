-- Revert supabase:0023_sync_registered_proprietors_to_customer_accounts to pg

BEGIN;

DROP TRIGGER IF EXISTS sync_rp_to_ca_on_registered_proprietors ON myenergy.registered_proprietors;
DROP FUNCTION IF EXISTS myenergy.sync_rp_to_ca();
DROP FUNCTION IF EXISTS myenergy.migrate_existing_rp_to_ca();

COMMIT;