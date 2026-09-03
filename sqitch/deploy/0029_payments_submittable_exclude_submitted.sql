-- Deploy supabase:0029_payments_submittable_exclude_submitted to pg
-- Replay protection for payments (26-27 Aug 2026 duplicate-charge incident).
--
-- The runner (check_payments_submittable) re-submits every row that
-- submittable_payments() returns, and - until this change - that was every
-- 'pending' row whose scheduled_at had passed, regardless of whether it had
-- already been submitted to Stripe. Nothing persisted the PaymentIntent id in
-- the payments row, so once Stripe's 24 h idempotency key (the payment id)
-- expired, the next tick charged the customer a second time (61 duplicate
-- charges, 27 Aug 2026).
--
-- With this guard a row can only ever be submitted once: submittable_payments()
-- now excludes rows that already carry a payment_intent or a submitted_at. This
-- is belt-and-braces with the app-side guard - the runner now persists the
-- PaymentIntent id and moves the row to status 'created' immediately after
-- submission - so that even if the DB write fails, the row is not re-charged.
--
-- Second guard: one payment may credit at most one topup. The composite PK
-- (payment_id, topup_id) does NOT prevent two different topups linking the same
-- payment, and the topups_payments_check_payment_unique trigger from 0000 is a
-- check-then-insert COUNT which is racy under concurrent inserts. This unique
-- index is the constraint the app-side replay protection relies on. Verified
-- before deploy: no duplicate payment_id rows exist.

BEGIN;

CREATE OR REPLACE FUNCTION myenergy.submittable_payments() RETURNS SETOF myenergy.payments
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT *
  FROM myenergy.payments
  WHERE status = 'pending'
  AND payment_intent IS NULL
  AND submitted_at IS NULL
  AND scheduled_at < now()
$$;

ALTER FUNCTION myenergy.submittable_payments() OWNER TO :"adminrole";

-- Cheap partial index covering exactly the rows submittable_payments() scans.
CREATE INDEX IF NOT EXISTS payments_pending_unsubmitted_idx
    ON myenergy.payments (scheduled_at)
    WHERE status = 'pending' AND payment_intent IS NULL AND submitted_at IS NULL;

-- Atomic guard: at most one topups_payments row per payment. Deploy fails here
-- if historical duplicates exist - check first (there were none on MGF at the
-- time of writing):
--   SELECT payment_id FROM myenergy.topups_payments GROUP BY 1 HAVING count(*) > 1;
CREATE UNIQUE INDEX IF NOT EXISTS topups_payments_payment_id_key
    ON myenergy.topups_payments (payment_id);

COMMIT;