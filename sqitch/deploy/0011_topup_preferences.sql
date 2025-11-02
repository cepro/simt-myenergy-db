-- Deploy supabase:0011_topup_preferences to pg

BEGIN;

CREATE TYPE myenergy.balance_strategy AS ENUM ('simple', 'smooth');

ALTER TABLE myenergy.wallets
    RENAME COLUMN topup_threshold TO target_balance;

ALTER TABLE myenergy.wallets
    RENAME COLUMN topup_amount TO minimum_balance;

ALTER TABLE myenergy.wallets
    ADD COLUMN balance_enum myenergy.balance_strategy;

ALTER TABLE myenergy.wallets
    ALTER COLUMN target_balance SET DEFAULT 30;

ALTER TABLE myenergy.wallets
    ALTER COLUMN minimum_balance SET DEFAULT 20;

COMMIT;
