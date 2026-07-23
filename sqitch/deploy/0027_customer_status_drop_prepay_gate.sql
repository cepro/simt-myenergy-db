-- Deploy supabase:0027_customer_status_drop_prepay_gate to pg
--
-- Prepay is decommissioned: prepay_enabled = true for 0 of 153 meters
-- (91 false, 62 NULL). The final prelive -> live gate in customer_status()
-- tested `m.prepay_enabled IS NOT TRUE`, which matches BOTH false and NULL,
-- so it blocked every meter in the system and stranded every fully-onboarded
-- customer at 'prelive'. This also blocked solar-credit application indirectly,
-- because monthly_solar_credits_unapplied() filters on c.status = 'live'.
--
-- This migration removes that gate entirely and drops the now-dead
-- `prepay_enabled` parameter from customer_status(). Of the five callers, only
-- meter_prepay_status_change() ever passed a non-NULL value (NEW.prepay_enabled),
-- and only when a meter's prepay_enabled changed -- which never happens anymore.
-- That function and its trigger are dropped. The two callers that passed NULL
-- positionally are updated to the 2-arg signature; the remaining two callers
-- already use a single positional argument and need no change.
--
-- Note: DEFAULT parameters still count toward a function's identity in
-- PostgreSQL, so CREATE OR REPLACE cannot drop the parameter. We DROP the old
-- 3-arg function explicitly, then CREATE the new 2-arg one.
--
-- NOTE: this only changes the function. It does NOT rewrite the stored
-- customers.status column. Run the recompute afterwards:
--
--   UPDATE myenergy.customers
--      SET status = myenergy.customer_status(customers, status)
--    WHERE status = 'prelive';

BEGIN;

-- 1. Drop the old 3-arg customer_status (cannot be done via CREATE OR REPLACE).
DROP FUNCTION IF EXISTS myenergy.customer_status(myenergy.customers, myenergy.customer_status_enum, boolean);

-- 2. Recreate as 2-arg, with the prepay meter gate removed. Body is otherwise
--    identical to the 0023 definition.
CREATE FUNCTION myenergy.customer_status(new_customer_row myenergy.customers, old_status myenergy.customer_status_enum DEFAULT NULL::myenergy.customer_status_enum)
 RETURNS myenergy.customer_status_enum
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    auth_user_email_count int;
    contract_count int;
    signed_contract_count int;
BEGIN
    -- If customer was previously 'live', only allow transition to 'exiting' or 'archived'
    IF old_status = 'live' THEN
        IF new_customer_row.exiting IS true THEN
            RETURN 'exiting'::myenergy.customer_status_enum;
        END IF;
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    -- cepro admin's are always live
    IF new_customer_row.cepro_user IS true THEN
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    -- exiting - flag explicitly set
    IF new_customer_row.exiting IS true THEN
        RETURN 'exiting'::myenergy.customer_status_enum;
    END IF;

    -- pending - not yet registered from app sign up form
    SELECT count(*) FROM auth.users WHERE "email" = new_customer_row.email INTO auth_user_email_count;
    IF auth_user_email_count = 0 THEN
        RETURN 'pending'::myenergy.customer_status_enum;
    END IF;

    -- Corporate body members are live once registered
    IF EXISTS (
        SELECT 1 FROM myenergy.customer_corporate_bodies
        WHERE customer = new_customer_row.id
    ) THEN
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    -- pre-onboarding - flag blocks transition to onboarding
    IF new_customer_row.allow_onboard_transition IS NOT TRUE THEN
        RETURN 'preonboarding'::myenergy.customer_status_enum;
    END IF;

    -- pre-onboarding - registered but contract records to sign
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

    -- get count of contracts signed by this customer
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

    -- onboarding - contracts exist but not all signed
    IF
        signed_contract_count != contract_count or
        new_customer_row.confirmed_details_at is null or
        new_customer_row.has_payment_method is not true
    THEN
        RETURN 'onboarding'::myenergy.customer_status_enum;
    END IF;

    -- live - all onboarding gates passed. The old prepay meter-readiness gate
    -- that lived here is removed: prepay is decommissioned (no meter is ever
    -- prepay_enabled), so the gate was dead logic that blocked everyone.
    RETURN 'live'::myenergy.customer_status_enum;
END;
$function$
;

-- 3. Update the two callers that passed a positional 3rd arg (NULL).
CREATE OR REPLACE FUNCTION myenergy.customer_status_update_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     new_status myenergy.customer_status_enum;
BEGIN
    SELECT myenergy.customer_status(NEW, NULL) INTO new_status;
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
        SELECT myenergy.customer_status(customer_row, customer_row.status) INTO new_status;
        RAISE NOTICE 'New status % for customer %', new_status, customer_id;

        UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;

        RAISE NOTICE 'Updated status for customer: %', customer_id;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 4. Drop the dead meter_prepay_status_change trigger + function. It only fired
--    when a meter's prepay_enabled changed (WHEN old.prepay_enabled IS DISTINCT
--    FROM new.prepay_enabled), which no longer happens, and was the only caller
--    that ever passed a real prepay_enabled value to customer_status().
DROP TRIGGER IF EXISTS meter_prepay_status_change_trigger ON myenergy.meters;
DROP FUNCTION IF EXISTS myenergy.meter_prepay_status_change();

COMMIT;
