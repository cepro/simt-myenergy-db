-- Revert supabase:0014_auto_topup from pg

BEGIN;

ALTER TABLE myenergy.wallets
    DROP COLUMN auto_topup;

COMMIT;
