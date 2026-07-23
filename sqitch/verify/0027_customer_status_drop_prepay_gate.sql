-- Verify supabase:0027_customer_status_drop_prepay_gate on pg

BEGIN;

-- customer_status is now 2-arg (no prepay_enabled parameter) and the old
-- 3-arg identity must be gone.
SELECT pg_get_functiondef('myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum)'::regprocedure);
SELECT 1 / COUNT(*)::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname = 'customer_status' AND n.nspname = 'myenergy'
   AND pg_get_function_identity_arguments(p.oid) LIKE '%, boolean%';

-- meter_prepay_status_change function + trigger must be gone.
SELECT 1 / COUNT(*)::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname = 'meter_prepay_status_change' AND n.nspname = 'myenergy';

SELECT 1 / COUNT(*)::int
  FROM pg_trigger
 WHERE tgname = 'meter_prepay_status_change_trigger';

ROLLBACK;
