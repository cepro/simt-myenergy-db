-- Deploy supabase:0014_auto_topup to pg

BEGIN;

ALTER TABLE myenergy.wallets
    ADD COLUMN auto_topup BOOLEAN NOT NULL DEFAULT TRUE;

COMMIT;
