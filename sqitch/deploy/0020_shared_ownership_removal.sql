-- Deploy supabase:0020_shared_ownership_removal to pg
-- Remove deprecated properties.owner column and update functions to use customer_accounts.role='owner'

BEGIN;

-- Drop trigger that references properties.owner before dropping the column
DROP TRIGGER IF EXISTS update_property_tenure_properties ON myenergy.properties;

-- Drop FK constraint on owner column
ALTER TABLE myenergy.properties DROP CONSTRAINT IF EXISTS properties_owner_fkey;

-- Drop the deprecated owner column
ALTER TABLE myenergy.properties DROP COLUMN IF EXISTS owner;

-- Drop the index on owner column (if it wasn't dropped with the column)
DROP INDEX IF EXISTS myenergy.properties_owner_idx;

-- Create OR REPLACE properties_owned() to use customer_accounts.role='owner'
CREATE OR REPLACE FUNCTION myenergy.properties_owned() RETURNS uuid[]
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT array_agg(DISTINCT p.id)::uuid[]
    FROM myenergy.properties p
    WHERE EXISTS (
        SELECT 1 FROM myenergy.accounts a
        JOIN myenergy.customer_accounts ca ON ca.account = a.id
        WHERE a.property = p.id
          AND ca.customer = myenergy.customer()
          AND ca.role = 'owner'
    )
$$;

-- Create OR REPLACE get_property_owners_for_auth_user() to use customer_accounts
CREATE OR REPLACE FUNCTION myenergy.get_property_owners_for_auth_user(email_in text) RETURNS SETOF uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ca.customer
    FROM myenergy.properties p
    JOIN myenergy.accounts a ON a.property = p.id
    JOIN myenergy.customer_accounts ca ON ca.account = a.id
    JOIN myenergy.customers c ON ca.customer = c.id
    WHERE c.email = email_in
      AND ca.role = 'owner';
END;
$$;

-- Create OR REPLACE update_property_tenure() to use customer_accounts instead of properties.owner
-- The tenure logic now checks if ANY owner differs from ANY occupier on the same account
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
                    FROM myenergy.customer_accounts ca_occ
                    JOIN myenergy.customer_accounts ca_own
                      ON ca_own.account = ca_occ.account
                    WHERE ca_occ.account = ANY(affected_properties)
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

-- Drop change_property_owner() as it referenced properties.owner which no longer exists
DROP FUNCTION IF EXISTS myenergy.change_property_owner(uuid, uuid);

-- Fix customer_invites_generate_invite_url() which referenced properties.owner
CREATE OR REPLACE FUNCTION myenergy.customer_invites_generate_invite_url()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
        app_url text;
    BEGIN
        SELECT e.app_url
        FROM myenergy.escos e
        WHERE e.id IN (
            SELECT p.esco
            FROM myenergy.properties p
            JOIN myenergy.accounts a ON a.property = p.id
            JOIN myenergy.customer_accounts ca ON ca.account = a.id
            WHERE ca.customer = NEW.customer
              AND ca.role = 'owner'
        ) INTO app_url;

        IF app_url is null THEN
            SELECT e.app_url
            FROM myenergy.escos e
            WHERE e.id IN (
                SELECT p.esco FROM myenergy.properties p
                JOIN myenergy.accounts a ON a.property = p.id
                JOIN myenergy.customer_accounts ca ON ca.account = a.id
                WHERE ca.customer = NEW.customer
            ) INTO app_url;
        END IF;

        IF app_url is not null THEN
            NEW.invite_url = app_url || '/invite/' || NEW.invite_token;
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'No esco is associated with this customer yet so an invite cannot be created';
        END IF;
    END;
    $function$
;

CREATE OR REPLACE FUNCTION myenergy.sync_flows_to_public_escos() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO myenergy.escos (id, created_at, name, code, app_url, region)
    SELECT id, created_at, name, code, app_url, region
    FROM flows.escos
    WHERE code NOT IN (SELECT code FROM myenergy.escos);
END;
$$;

GRANT EXECUTE ON FUNCTION myenergy.auth_user_id_for_customer TO anon;

COMMIT;
