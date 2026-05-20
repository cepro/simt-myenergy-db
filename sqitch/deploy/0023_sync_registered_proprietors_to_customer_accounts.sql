-- Deploy supabase:0023_sync_registered_proprietors_to_customer_accounts to pg
-- Add trigger to sync registered_proprietors inserts to customer_accounts (role='owner') for solar accounts

BEGIN;

-- Function to sync registered_proprietors to customer_accounts
-- Creates customer_accounts entries with role='owner' for solar accounts when a registered_proprietor is added
CREATE OR REPLACE FUNCTION myenergy.sync_rp_to_ca()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    solar_account_id uuid;
BEGIN
    -- Find solar account(s) for this property and insert owner entries
    -- Using ON CONFLICT DO NOTHING to handle duplicate inserts gracefully
    FOR solar_account_id IN
        SELECT a.id
        FROM myenergy.accounts a
        WHERE a.property = NEW.property
          AND a.type = 'solar'
    LOOP
        INSERT INTO myenergy.customer_accounts (customer, account, role)
        VALUES (NEW.customer, solar_account_id, 'owner')
        ON CONFLICT (customer, account, role) DO NOTHING;
    END LOOP;

    RETURN NEW;
END;
$$;

-- Trigger on registered_proprietors INSERT
DROP TRIGGER IF EXISTS sync_rp_to_ca_on_registered_proprietors ON myenergy.registered_proprietors;
CREATE TRIGGER sync_rp_to_ca_on_registered_proprietors
    AFTER INSERT ON myenergy.registered_proprietors
    FOR EACH ROW EXECUTE FUNCTION myenergy.sync_rp_to_ca();

-- Function to migrate existing registered_proprietors to customer_accounts
-- Can be called manually or used for backfilling existing data
CREATE OR REPLACE FUNCTION myenergy.migrate_existing_rp_to_ca()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    row_count integer;
BEGIN
    -- For each registered_proprietor, find solar accounts and create customer_accounts entries
    INSERT INTO myenergy.customer_accounts (customer, account, role)
    SELECT DISTINCT rp.customer, a.id, 'owner'::myenergy.account_role_type_enum
    FROM myenergy.registered_proprietors rp
    JOIN myenergy.accounts a ON a.property = rp.property AND a.type = 'solar'
    WHERE NOT EXISTS (
        SELECT 1 FROM myenergy.customer_accounts ca
        WHERE ca.customer = rp.customer
          AND ca.account = a.id
          AND ca.role = 'owner'
    );

    GET DIAGNOSTICS row_count = ROW_COUNT;
    RETURN row_count;
END;
$$;

-- Fix customer_status() to use contracts.signed boolean instead of deprecated signed_date column
-- (signed_date was dropped in 0022_contract_signatures.sql)
CREATE OR REPLACE FUNCTION myenergy.customer_status(new_customer_row myenergy.customers, old_status myenergy.customer_status_enum DEFAULT NULL::myenergy.customer_status_enum, prepay_enabled boolean DEFAULT NULL::boolean)
 RETURNS myenergy.customer_status_enum
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    auth_user_email_count int;
    contract_count int;
    signed_contract_count int;
    has_unprepared_supply_meter boolean;
BEGIN
    IF old_status = 'live' THEN
        IF new_customer_row.exiting IS true THEN
            RETURN 'exiting'::myenergy.customer_status_enum;
        END IF;
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    IF new_customer_row.cepro_user IS true THEN
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    IF new_customer_row.exiting IS true THEN
        RETURN 'exiting'::myenergy.customer_status_enum;
    END IF;

    SELECT count(*) FROM auth.users WHERE "email" = new_customer_row.email INTO auth_user_email_count;
    IF auth_user_email_count = 0 THEN
        RETURN 'pending'::myenergy.customer_status_enum;
    END IF;

    IF EXISTS (
        SELECT 1 FROM myenergy.customer_corporate_bodies
        WHERE customer = new_customer_row.id
    ) THEN
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    IF new_customer_row.allow_onboard_transition IS NOT TRUE THEN
        RETURN 'preonboarding'::myenergy.customer_status_enum;
    END IF;

    SELECT count(*) FROM myenergy.accounts a
    JOIN myenergy.customer_accounts ca ON ca.account = a.id
    LEFT JOIN myenergy.contracts c ON c.id = a.current_contract
    WHERE a.current_contract is not null
    AND ca.customer = new_customer_row.id
    AND NOT (
        (ca.role = 'owner' AND (c.type = 'supply' OR a.type = 'supply'))
        OR
        (ca.role = 'occupier' AND (c.type = 'solar' OR a.type = 'solar'))
    )
    INTO contract_count;

    IF contract_count = 0 THEN
        RETURN 'preonboarding'::myenergy.customer_status_enum;
    END IF;

    SELECT count(*) FROM myenergy.accounts a
    JOIN myenergy.customer_accounts ca ON ca.account = a.id
    LEFT JOIN myenergy.contracts c ON c.id = a.current_contract
    WHERE ca.customer = new_customer_row.id
    AND a.current_contract IN (
        SELECT id from myenergy.contracts where signed = true
    )
    AND NOT (
        (ca.role = 'owner' AND (c.type = 'supply' OR a.type = 'supply'))
        OR
        (ca.role = 'occupier' AND (c.type = 'solar' OR a.type = 'solar'))
    )
    INTO signed_contract_count;

    IF
        signed_contract_count != contract_count or
        new_customer_row.confirmed_details_at is null or
        new_customer_row.has_payment_method is not true
    THEN
        RETURN 'onboarding'::myenergy.customer_status_enum;
    END IF;

    IF prepay_enabled is true THEN
        has_unprepared_supply_meter = false;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM myenergy.customer_accounts ca
            JOIN myenergy.accounts a ON a.id = ca.account
            JOIN myenergy.properties p ON p.id = a.property
            JOIN myenergy.meters m ON m.id = p.supply_meter
            WHERE ca.customer = new_customer_row.id
            AND ca.role = 'occupier'
            AND a.type = 'supply'
            AND (m.prepay_enabled IS NOT TRUE)
        ) INTO has_unprepared_supply_meter;
    END IF;

    IF has_unprepared_supply_meter THEN
        RETURN 'prelive'::myenergy.customer_status_enum;
    END IF;

    RETURN 'live'::myenergy.customer_status_enum;
END;
$function$
;

COMMIT;