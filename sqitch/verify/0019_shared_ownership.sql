-- Verify supabase:0019_shared_ownership on pg

BEGIN;

SELECT 1 FROM myenergy.corporate_bodies WHERE FALSE;
SELECT 1 FROM myenergy.customer_corporate_bodies WHERE FALSE;
SELECT 1 FROM myenergy.registered_proprietors WHERE FALSE;

ROLLBACK;
