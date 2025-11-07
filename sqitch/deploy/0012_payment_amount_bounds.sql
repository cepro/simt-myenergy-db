-- Deploy supabase:0012_payment_amount_bounds to pg

BEGIN;

-- Drop the existing constraint
ALTER TABLE myenergy.payments
    DROP CONSTRAINT IF EXISTS payments_amount_check;

-- Add new constraint with updated bounds: > 0 and <= 500 pence (£5.00)
ALTER TABLE myenergy.payments
    ADD CONSTRAINT payments_amount_check
    CHECK ((amount_pence > 0) AND (amount_pence <= 50000));

COMMIT;
