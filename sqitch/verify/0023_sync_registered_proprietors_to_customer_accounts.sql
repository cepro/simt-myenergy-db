-- Verify supabase:0023_sync_registered_proprietors_to_customer_accounts

BEGIN;

-- Check trigger exists
SELECT 1 FROM pg_trigger tg
WHERE tgname = 'sync_rp_to_ca_on_registered_proprietors'
  AND tgrelid = 'myenergy.registered_proprietors'::regclass;

-- Check function exists
SELECT 1 FROM pg_proc p
WHERE p.proname = 'sync_rp_to_ca'
  AND p.pronamespace = 'myenergy'::regnamespace;

-- Check migrate function exists
SELECT 1 FROM pg_proc p
WHERE p.proname = 'migrate_existing_rp_to_ca'
  AND p.pronamespace = 'myenergy'::regnamespace;

ROLLBACK;