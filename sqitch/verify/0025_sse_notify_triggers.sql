-- Verify supabase:0025_sse_notify_triggers on pg

BEGIN;

SELECT pg_get_functiondef('myenergy.customers_sse_notify()'::regprocedure);
SELECT pg_get_functiondef('myenergy.contracts_sse_notify()'::regprocedure);

SELECT 1
FROM pg_trigger
WHERE tgname = 'customers_sse_notify_trg'
  AND tgrelid = 'myenergy.customers'::regclass;

SELECT 1
FROM pg_trigger
WHERE tgname = 'contracts_sse_notify_trg'
  AND tgrelid = 'myenergy.contracts'::regclass;

ROLLBACK;
