-- Deploy supabase:0028_tenure_registered_proprietors_aware to pg
-- Make property tenure aware of registered_proprietors and re-evaluate it when they change.
--
-- Background: update_property_tenure() only compared owner vs occupier
-- customer_accounts rows on the SAME account, and the trigger only fired on
-- customer_accounts / accounts changes. registered_proprietors (the source of truth
-- for property ownership) were never considered. As a result, supply-only
-- properties -- which have no solar account, so the registered_proprietors ->
-- customer_accounts (role='owner') sync added in 0023 is a no-op and never creates
-- an owner row -- could not be classified as separate_owner_and_occupier even when
-- the registered proprietor differed from the occupier, and adding/changing a
-- registered_proprietor never re-evaluated tenure.
--
-- This migration centralises the tenure decision in tenure_for_property(uuid),
-- which treats owners as (customer_accounts role='owner') UNION
-- registered_proprietors and occupiers as customer_accounts role='occupier', and
-- makes the trigger fire on registered_proprietors too.
--
-- It is a no-op on current data: recomputing tenure with the new logic reproduces
-- the stored tenure for every property (0 rows change in the backfill below). It
-- also protects the 2 properties whose stored tenure (separate) already diverged
-- from the old same-account heuristic -- those are genuine landlord/tenant cases
-- whose owner and occupier live on different accounts, which the old heuristic
-- could not express and would wrongly downgrade if the trigger fired on them.

BEGIN;

-- Single source of truth for a property's tenure.
-- separate_owner_and_occupier iff some owner differs from some occupier on the
-- property; else single_owner_occupier.
--   owners    = customer_accounts role='owner' (e.g. solar accounts) UNION registered_proprietors
--   occupiers = customer_accounts role='occupier'
CREATE OR REPLACE FUNCTION myenergy.tenure_for_property(p_id uuid)
RETURNS myenergy.property_tenure_enum
LANGUAGE sql
STABLE
AS $$
    SELECT CASE WHEN EXISTS (
        SELECT 1
        FROM (
            SELECT a.property, ca.customer
            FROM myenergy.accounts a
            JOIN myenergy.customer_accounts ca ON ca.account = a.id AND ca.role = 'owner'
            UNION
            SELECT rp.property, rp.customer
            FROM myenergy.registered_proprietors rp
        ) o
        JOIN (
            SELECT a.property, ca.customer
            FROM myenergy.accounts a
            JOIN myenergy.customer_accounts ca ON ca.account = a.id AND ca.role = 'occupier'
        ) e ON e.property = o.property
        WHERE o.property = p_id AND o.customer <> e.customer
    )
    THEN 'separate_owner_and_occupier'::myenergy.property_tenure_enum
    ELSE 'single_owner_occupier'::myenergy.property_tenure_enum
    END
$$;

-- Re-evaluate tenure for the affected property(ies) via tenure_for_property, now
-- considering registered_proprietors.
CREATE OR REPLACE FUNCTION myenergy.update_property_tenure()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    affected_properties uuid[];
BEGIN
    IF TG_TABLE_NAME = 'customer_accounts' THEN
        IF TG_OP = 'DELETE' THEN
            SELECT ARRAY_AGG(DISTINCT a.property)
            INTO affected_properties
            FROM myenergy.accounts a
            WHERE a.id = OLD.account;
        ELSE
            SELECT ARRAY_AGG(DISTINCT a.property)
            INTO affected_properties
            FROM myenergy.accounts a
            WHERE a.id = NEW.account;
        END IF;
    ELSIF TG_TABLE_NAME = 'registered_proprietors' THEN
        IF TG_OP = 'DELETE' THEN
            affected_properties := ARRAY[OLD.property];
        ELSE
            affected_properties := ARRAY[NEW.property];
        END IF;
    ELSIF TG_TABLE_NAME = 'accounts' THEN
        IF TG_OP = 'DELETE' THEN
            affected_properties := ARRAY[OLD.property];
        ELSE
            affected_properties := ARRAY[NEW.property];
        END IF;
    END IF;

    IF affected_properties IS NOT NULL AND array_length(affected_properties, 1) > 0 THEN
        UPDATE myenergy.properties p
        SET tenure = myenergy.tenure_for_property(p.id)
        WHERE p.id = ANY(affected_properties);
    END IF;

    RETURN NULL;
END;
$$;

-- Re-evaluate tenure when registered_proprietors change. Previously only
-- customer_accounts and accounts changes did; for supply-only properties an RP
-- insert/change never reached update_property_tenure (the 0023 sync_rp_to_ca is a
-- no-op without a solar account).
DROP TRIGGER IF EXISTS update_property_tenure_registered_proprietors ON myenergy.registered_proprietors;
CREATE TRIGGER update_property_tenure_registered_proprietors
    AFTER INSERT OR UPDATE OR DELETE ON myenergy.registered_proprietors
    FOR EACH ROW EXECUTE FUNCTION myenergy.update_property_tenure();

-- Backfill: recompute tenure for every property whose stored value no longer
-- matches the new logic. No-op on current data; guarantees consistency and that
-- tenure_for_property is exercised across all properties.
UPDATE myenergy.properties p
SET tenure = myenergy.tenure_for_property(p.id)
WHERE p.tenure IS DISTINCT FROM myenergy.tenure_for_property(p.id);

COMMIT;
