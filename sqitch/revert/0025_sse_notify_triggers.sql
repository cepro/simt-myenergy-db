-- Revert supabase:0025_sse_notify_triggers from pg

BEGIN;

DROP TRIGGER IF EXISTS contracts_sse_notify_trg ON myenergy.contracts;
DROP TRIGGER IF EXISTS customers_sse_notify_trg ON myenergy.customers;

DROP FUNCTION IF EXISTS myenergy.contracts_sse_notify();
DROP FUNCTION IF EXISTS myenergy.customers_sse_notify();

COMMIT;
