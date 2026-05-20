-- Revert supabase:0020_shared_ownership_removal from pg

BEGIN;

-- Re-add the owner column (IF NOT EXISTS to handle revert ordering)
ALTER TABLE myenergy.properties ADD COLUMN IF NOT EXISTS owner uuid;

-- Re-add the FK constraint
ALTER TABLE myenergy.properties ADD CONSTRAINT properties_owner_fkey
    FOREIGN KEY (owner) REFERENCES myenergy.customers(id)
    ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

-- Re-add the index
CREATE INDEX properties_owner_idx ON myenergy.properties USING btree (owner);

-- Re-create change_property_owner() function
CREATE FUNCTION myenergy.change_property_owner(property_id uuid, new_owner uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE myenergy.properties
    SET owner = new_owner
    WHERE id = property_id;

    UPDATE myenergy.customer_accounts
    SET customer = new_owner
    WHERE account IN (SELECT id FROM myenergy.accounts WHERE property = property_id)
      AND role = 'owner';
END;
$$;

-- Re-create update_property_tenure() with original logic
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
    ELSIF TG_TABLE_NAME = 'properties' THEN
        IF TG_OP = 'DELETE' THEN
            affected_properties := ARRAY[OLD.id];
        ELSE
            affected_properties := ARRAY[NEW.id];
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
                    JOIN myenergy.customer_accounts ca ON ca.account = a.id
                    WHERE a.property = p.id
                      AND ca.role = 'occupier'
                      AND ca.customer != p.owner
                ) THEN 'separate_owner_and_occupier'::myenergy.property_tenure_enum
                ELSE 'single_owner_occupier'::myenergy.property_tenure_enum
            END
        WHERE p.id = ANY(affected_properties);
    END IF;

    RETURN NULL;
END;
$$;

-- Re-create properties_owned() with original logic
CREATE OR REPLACE FUNCTION myenergy.properties_owned() RETURNS uuid[]
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT array_agg(p.id)::uuid[]
    FROM myenergy.properties p
    WHERE p.owner = myenergy.customer()
$$;

-- Re-create get_property_owners_for_auth_user() with original logic
CREATE OR REPLACE FUNCTION myenergy.get_property_owners_for_auth_user(email_in text) RETURNS SETOF uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT p.owner
    FROM myenergy.properties p
    JOIN myenergy.accounts a ON a.property = p.id
    JOIN myenergy.customer_accounts ca ON ca.account = a.id
    JOIN myenergy.customers c ON ca.customer = c.id
    WHERE c.email = email_in;
END;
$$;

-- Re-create trigger (after function exists)
CREATE TRIGGER update_property_tenure_properties
    AFTER UPDATE OF owner ON myenergy.properties
    FOR EACH ROW EXECUTE FUNCTION myenergy.update_property_tenure();

COMMIT;