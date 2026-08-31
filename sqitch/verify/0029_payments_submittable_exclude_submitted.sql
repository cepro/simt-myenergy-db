-- Verify supabase:0029_payments_submittable_exclude_submitted on pg

BEGIN;

-- The guard predicate is present in the function body...
DO $$
DECLARE
  def text;
BEGIN
  SELECT pg_get_functiondef('myenergy.submittable_payments()'::regprocedure) INTO def;
  IF position('payment_intent is null' in lower(def)) = 0
     OR position('submitted_at is null' in lower(def)) = 0 THEN
    RAISE EXCEPTION 'submittable_payments() does not exclude already-submitted payments';
  END IF;

  -- ...and the partial index exists.
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname = 'myenergy' AND tablename = 'payments'
       AND indexname = 'payments_pending_unsubmitted_idx'
  ) THEN
    RAISE EXCEPTION 'partial index payments_pending_unsubmitted_idx missing';
  END IF;
END $$;

-- Sanity: the guard changes nothing for clean, never-submitted pending rows.
SELECT count(*) FROM myenergy.payments
WHERE status = 'pending' AND payment_intent IS NULL AND submitted_at IS NULL;

ROLLBACK;