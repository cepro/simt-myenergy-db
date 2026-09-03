-- Revert supabase:0029_payments_submittable_exclude_submitted from pg

BEGIN;

-- Restore the pre-0029 submittable_payments(): anything pending and due is
-- selectable regardless of prior submission state. This is the behaviour that
-- allowed the 27 Aug 2026 duplicate charges once the 24 h idempotency key
-- expired - revert only deliberately.
CREATE OR REPLACE FUNCTION myenergy.submittable_payments() RETURNS SETOF myenergy.payments
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT *
  FROM myenergy.payments
  WHERE status = 'pending'
  AND scheduled_at < now()
$$;

ALTER FUNCTION myenergy.submittable_payments() OWNER TO :"adminrole";

DROP INDEX IF EXISTS myenergy.payments_pending_unsubmitted_idx;
DROP INDEX IF EXISTS myenergy.topups_payments_payment_id_key;

COMMIT;