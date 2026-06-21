-- Deploy supabase:0025_sse_notify_triggers to pg
-- NOTIFY triggers that feed the accounts service SSE change feed.
--
-- Replaces the previous in-process Spring ApplicationEvent publishing that
-- lived in AccountsServiceImpl and DocusealWebhookController. Those
-- publications only fired on code paths the Java side actually ran, which
-- silently dropped SSE events for:
--
--   * customer.status transitions driven by myenergy.customer_status()
--     (triggered by BEFORE UPDATE on customers via customer_status_update_on_trigger
--      from migration 0019 / 0022)
--   * status flips driven by auth.users updates
--     (customer_status_auth_users_update from 0019)
--   * contract.signed flips written by the contract_signatures trigger
--     (update_contract_signed_status from 0022) which is entirely on the
--     DB side
--   * any other writer of these rows (admin SQL, sqitch seed, future services)
--
-- The triggers below fire for *every* UPDATE that affects the tracked
-- columns, regardless of which code path wrote the row. Channels:
--
--   customer_updated - fires when status, has_payment_method or
--                       allow_onboard_transition changes
--   contract_signed   - fires once on the false -> true edge of
--                       contracts.signed (the threshold the SSE consumer
--                       keys off)
--
-- Payload is intentionally minimal: just the row's UUID. The Java
-- handler (CustomerUpdatedNotifierHandler / ContractSignedNotifierHandler
-- in simt-j-accountservice) does a single-row lookup of the full record
-- via the existing GraphQL backend-user path and forwards the
-- CustomerEventDto / ContractEventDto to the SSE publisher. This keeps
-- the trigger simple, keeps the WAL payload trivially small, and means
-- the Java side always sees the freshly-committed row even if the
-- state that the trigger observed in NEW is stale relative to the
-- real wire payload the SSE consumer expects.

BEGIN;

-- customers --------------------------------------------------------------

CREATE OR REPLACE FUNCTION myenergy.customers_sse_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- AFTER UPDATE: the customer_status_update_on_trigger (BEFORE UPDATE)
    -- may have already mutated NEW.status, so this view is the row as it
    -- actually went to disk. The IS DISTINCT FROM guard handles nulls
    -- correctly and keeps no-op updates (e.g. fullname-only writes) from
    -- spamming the channel.
    IF NEW.status                  IS DISTINCT FROM OLD.status
    OR NEW.has_payment_method      IS DISTINCT FROM OLD.has_payment_method
    OR NEW.allow_onboard_transition IS DISTINCT FROM OLD.allow_onboard_transition
    THEN
        PERFORM pg_notify(
            'customer_updated',
            json_build_object('id', NEW.id)::text
        );
    END IF;
    RETURN NULL;  -- AFTER trigger; return value is ignored
END;
$$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'customers_sse_notify_trg') THEN
        CREATE TRIGGER customers_sse_notify_trg
            AFTER UPDATE ON myenergy.customers
            FOR EACH ROW EXECUTE FUNCTION myenergy.customers_sse_notify();
    END IF;
END $$;

-- contracts --------------------------------------------------------------

CREATE OR REPLACE FUNCTION myenergy.contracts_sse_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Fire only on the false -> true edge. The contract_signatures
    -- trigger (update_contract_signed_status, migration 0022) issues
    -- the canonical UPDATE contracts SET signed = true once the signature
    -- count threshold is crossed. The OLD.signed = true, NEW.signed = true
    -- case is filtered out by the IS DISTINCT FROM guard so the event
    -- fires exactly once per contract lifetime.
    IF NEW.signed IS DISTINCT FROM OLD.signed AND NEW.signed = true THEN
        PERFORM pg_notify(
            'contract_signed',
            json_build_object('id', NEW.id)::text
        );
    END IF;
    RETURN NULL;
END;
$$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'contracts_sse_notify_trg') THEN
        CREATE TRIGGER contracts_sse_notify_trg
            AFTER UPDATE OF signed ON myenergy.contracts
            FOR EACH ROW EXECUTE FUNCTION myenergy.contracts_sse_notify();
    END IF;
END $$;

COMMIT;
