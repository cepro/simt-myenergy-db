-- Revert supabase:0027_customer_status_drop_prepay_gate from pg
--
-- Restores the 3-arg customer_status() with the prepay meter-readiness gate
-- (`m.prepay_enabled IS NOT TRUE`), the two callers that passed a positional
-- NULL, and the meter_prepay_status_change trigger + function. Mirrors the
-- pre-0027 state defined in 0023 / 0001.

BEGIN;

-- 1. Recreate the dead meter_prepay_status_change trigger + function.
CREATE OR REPLACE FUNCTION myenergy.meter_prepay_status_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    customer_ids uuid[];
    customer_row myenergy.customers;
    new_status myenergy.customer_status_enum;
    customer_id uuid;
BEGIN
    -- Find customers who are occupiers of supply accounts using this meter
    SELECT array_agg(DISTINCT ca.customer)
    FROM myenergy.customer_accounts ca
    JOIN myenergy.accounts a ON a.id = ca.account
    JOIN myenergy.properties p ON p.id = a.property
    WHERE p.supply_meter = NEW.id
    AND ca.role = 'occupier'
    AND a.type = 'supply'
    INTO customer_ids;

    -- Update status for these customers
    IF customer_ids IS NOT NULL AND array_length(customer_ids, 1) > 0 THEN
        FOR i IN 1..array_length(customer_ids, 1) LOOP
            customer_id := customer_ids[i];

            SELECT * FROM myenergy.customers WHERE id = customer_id INTO customer_row;

            -- Pass current status as old_status
            SELECT myenergy.customer_status(customer_row, customer_row.status, NEW.prepay_enabled) INTO new_status;
            UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'meter_prepay_status_change_trigger') THEN
        CREATE CONSTRAINT TRIGGER meter_prepay_status_change_trigger
            AFTER UPDATE OF prepay_enabled ON myenergy.meters
            DEFERRABLE INITIALLY DEFERRED
            FOR EACH ROW
            WHEN ((old.prepay_enabled IS DISTINCT FROM new.prepay_enabled))
            EXECUTE FUNCTION myenergy.meter_prepay_status_change();
    END IF;
END $$;

-- 2. Restore the two callers that passed a positional 3rd arg (NULL).
CREATE OR REPLACE FUNCTION myenergy.customer_status_update_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     new_status myenergy.customer_status_enum;
BEGIN
    SELECT myenergy.customer_status(NEW, NULL, NULL) INTO new_status;
    NEW.status = new_status;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION myenergy.accounts_current_contract_update_customer_status_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     customer_id uuid;
     customer_row myenergy.customers;
     new_status "myenergy"."customer_status_enum";
BEGIN
    FOR customer_id IN
        SELECT "customer"
        FROM "myenergy"."customer_accounts"
        WHERE account = NEW.id
    LOOP
        -- Get current customer record
        SELECT * FROM "myenergy"."customers"
        WHERE id = customer_id
        INTO customer_row;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer not found with ID: %', customer_id;
        END IF;

        -- Calculate and update new status (pass current status as old_status)
        SELECT myenergy.customer_status(customer_row, customer_row.status, NULL) INTO new_status;
        RAISE NOTICE 'New status % for customer %', new_status, customer_id;

        UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;

        RAISE NOTICE 'Updated status for customer: %', customer_id;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 3. Restore the 3-arg customer_status() with the prepay meter gate. Drop the
--    2-arg version first (CREATE OR REPLACE cannot change the parameter list).
DROP FUNCTION IF EXISTS myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum);
DROP FUNCTION IF EXISTS myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum, boolean);

CREATE FUNCTION myenergy.customer_status(new_customer_row myenergy.customers, old_status myenergy.customer_status_enum DEFAULT NULL::myenergy.customer_status_enum, prepay_enabled boolean DEFAULT NULL::boolean)
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

    -- Check if this customer is an occupier on any supply account with unprepared meter
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

    -- prelive - all onboarding complete but supply meter not prepay_enabled
    IF has_unprepared_supply_meter THEN
        RETURN 'prelive'::myenergy.customer_status_enum;
    END IF;

    -- live - contracts have been signed and supply meter is ready
    RETURN 'live'::myenergy.customer_status_enum;
END;
$function$
;

COMMIT;
