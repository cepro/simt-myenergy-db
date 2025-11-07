-- Verify supabase:0012_payment_amount_bounds on pg

BEGIN;

-- Verify the constraint exists with the correct bounds
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'payments_amount_check'
        AND conrelid = 'myenergy.payments'::regclass
    ) THEN
        RAISE EXCEPTION 'Constraint payments_amount_check does not exist';
    END IF;
END $$;

-- Verify the constraint definition includes the correct bounds
SELECT 1/COUNT(*)
FROM pg_constraint
WHERE conname = 'payments_amount_check'
AND conrelid = 'myenergy.payments'::regclass
AND pg_get_constraintdef(oid) LIKE '%amount_pence > 0%'
AND pg_get_constraintdef(oid) LIKE '%amount_pence <= 50000%';

ROLLBACK;
