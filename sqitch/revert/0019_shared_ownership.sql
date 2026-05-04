-- Revert supabase:0019_shared_ownership from pg

BEGIN;

-- Restore customer_status() without corporate body check and with IS NULL prepay condition
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
        SELECT id from myenergy.contracts where signed_date is NOT null
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
            AND (m.prepay_enabled IS NULL)
        ) INTO has_unprepared_supply_meter;
    END IF;

    IF has_unprepared_supply_meter THEN
        RETURN 'prelive'::myenergy.customer_status_enum;
    END IF;

    RETURN 'live'::myenergy.customer_status_enum;
END;
$function$
;

-- Restore trigger to pass OLD.status
CREATE OR REPLACE FUNCTION myenergy.customer_status_update_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     new_status myenergy.customer_status_enum;
BEGIN
    SELECT myenergy.customer_status(NEW, OLD.status, NULL) INTO new_status;
    NEW.status = new_status;
    RETURN NEW;
END;
$$;

-- Drop auth.users triggers
DROP TRIGGER IF EXISTS update_customers_on_email_update_trigger ON auth.users;
DROP TRIGGER IF EXISTS customer_registration_trigger ON auth.users;
DROP TRIGGER IF EXISTS customer_status_auth_users_update ON auth.users;

-- Drop tables
DROP TABLE IF EXISTS myenergy.registered_proprietors;
DROP TABLE IF EXISTS myenergy.customer_corporate_bodies;
DROP TABLE IF EXISTS myenergy.corporate_bodies;

-- Restore properties.owner column
ALTER TABLE myenergy.properties ADD COLUMN owner uuid;

COMMIT;
