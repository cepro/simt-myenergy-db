-- Deploy supabase:0011_topup_preferences to pg

BEGIN;

CREATE TYPE myenergy.balance_strategy_enum AS ENUM ('simple', 'smooth');

CREATE TYPE myenergy.payment_timing_enum AS ENUM ('monthly', 'weekly');

ALTER TABLE myenergy.wallets
    RENAME COLUMN topup_threshold TO target_balance;

ALTER TABLE myenergy.wallets
    RENAME COLUMN topup_amount TO minimum_balance;

ALTER TABLE myenergy.wallets
    ADD COLUMN balance_enum myenergy.balance_strategy_enum;

ALTER TABLE myenergy.wallets
    ADD COLUMN payment_timing myenergy.payment_timing_enum;

ALTER TABLE myenergy.wallets
    ALTER COLUMN target_balance SET DEFAULT 30;

ALTER TABLE myenergy.wallets
    ALTER COLUMN minimum_balance SET DEFAULT 20;

ALTER TABLE myenergy.wallets
    ALTER COLUMN payment_timing SET DEFAULT 'monthly';

COMMIT;
