-- Revert supabase:0012_payment_amount_bounds from pg

BEGIN;

-- Drop the constraint with new bounds
ALTER TABLE myenergy.payments
    DROP CONSTRAINT IF EXISTS payments_amount_check;

-- Restore original constraint: > 0 and <= 100000 pence (£1000.00)
ALTER TABLE myenergy.payments
    ADD CONSTRAINT payments_amount_check
    CHECK ((amount_pence > 0) AND (amount_pence <= 100000));

COMMIT;
