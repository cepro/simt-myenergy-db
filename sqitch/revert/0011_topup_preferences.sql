-- Revert supabase:0011_topup_preferences from pg

BEGIN;

ALTER TABLE myenergy.wallets
    DROP COLUMN balance_enum;

ALTER TABLE myenergy.wallets
    DROP COLUMN payment_timing;

ALTER TABLE myenergy.wallets
    RENAME COLUMN target_balance TO topup_threshold;

ALTER TABLE myenergy.wallets
    RENAME COLUMN minimum_balance TO topup_amount;

DROP TYPE myenergy.balance_strategy_enum;

DROP TYPE myenergy.payment_timing_enum;

COMMIT;
