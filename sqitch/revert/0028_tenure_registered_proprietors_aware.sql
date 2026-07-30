-- Revert supabase:0028_tenure_registered_proprietors_aware from pg
--
-- Restores the pre-0028 update_property_tenure() (the 0020 same-account
-- owner/occupier heuristic), drops the registered_proprietors tenure trigger and
-- the tenure_for_property helper. Does not revert the tenure backfill (it changed
-- no rows on deploy); stored tenure is left as-is.

BEGIN;

DROP TRIGGER IF EXISTS update_property_tenure_registered_proprietors ON myenergy.registered_proprietors;

-- Restore the pre-0028 trigger body (0020 same-account owner vs occupier heuristic).
CREATE OR REPLACE FUNCTION myenergy.update_property_tenure() RETURNS trigger
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
    ELSIF TG_TABLE_NAME = 'accounts' THEN
        IF TG_OP = 'DELETE' THEN
            affected_properties := ARRAY[OLD.property];
        ELSE
            affected_properties := ARRAY[NEW.property];
        END IF;
    END IF;

    IF affected_properties IS NOT NULL AND array_length(affected_properties, 1) > 0 THEN
        UPDATE myenergy.properties p
        SET tenure =
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM myenergy.accounts a
                    JOIN myenergy.customer_accounts ca_occ
                      ON ca_occ.account = a.id
                    JOIN myenergy.customer_accounts ca_own
                      ON ca_own.account = a.id
                    WHERE a.property = ANY(affected_properties)
                      AND ca_occ.role = 'occupier'
                      AND ca_own.role = 'owner'
                      AND ca_occ.customer != ca_own.customer
                ) THEN 'separate_owner_and_occupier'::myenergy.property_tenure_enum
                ELSE 'single_owner_occupier'::myenergy.property_tenure_enum
            END
        WHERE p.id = ANY(affected_properties);
    END IF;

    RETURN NULL;
END;
$$;

DROP FUNCTION IF EXISTS myenergy.tenure_for_property(uuid);

COMMIT;
