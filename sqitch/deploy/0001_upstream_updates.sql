BEGIN;

DROP FUNCTION IF EXISTS myenergy.customer_status(myenergy.customers);

-- Replace the existing customer_status function with one that takes optional old_status
CREATE OR REPLACE FUNCTION myenergy.customer_status(
    new_customer_row myenergy.customers, 
    old_status myenergy.customer_status_enum DEFAULT NULL,
    prepay_enabled boolean DEFAULT NULL::boolean
) RETURNS myenergy.customer_status_enum
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    auth_user_email_count int;
    contract_count int;
    signed_contract_count int;
    has_unprepared_supply_meter boolean;
BEGIN
    -- If customer was previously 'live', only allow transition to 'exiting' or 'archived'
    IF old_status = 'live' THEN
        -- exiting - flag explicitly set
        IF new_customer_row.exiting IS true THEN
            RETURN 'exiting'::myenergy.customer_status_enum;
        END IF;
        
        -- TODO: Add logic for 'archived' status when that business rule is defined
        -- For now, once live, stay live unless exiting
        RETURN 'live'::myenergy.customer_status_enum;
    END IF;

    -- If no old_status provided or old_status is not 'live', compute status normally
    
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
        SELECT id from myenergy.contracts where signed_date is NOT null
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
    
    -- Check if this customer is an occupier on any supply account with unprepared meter
	IF prepay_enabled is true
	THEN
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
            AND (m.prepay_enabled IS NULL OR m.prepay_enabled = false)
        ) INTO has_unprepared_supply_meter;
    END IF;

    -- prelive - all onboarding complete but supply meter not prepay_enabled
    IF has_unprepared_supply_meter THEN
        RETURN 'prelive'::myenergy.customer_status_enum;
    END IF;

    -- live - contracts have been signed and supply meter is ready
    RETURN 'live'::myenergy.customer_status_enum;
END;
$$;

-- Update the trigger function to pass the old status
CREATE OR REPLACE FUNCTION myenergy.customer_status_update_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     new_status myenergy.customer_status_enum;
BEGIN
    -- Pass the OLD.status to the customer_status function
    SELECT myenergy.customer_status(NEW, OLD.status, NULL) INTO new_status; 
    NEW.status = new_status;
    RETURN NEW;
END;
$$;

-- Update other trigger functions that call customer_status to pass old status
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

CREATE OR REPLACE FUNCTION myenergy.contracts_signed_update_customer_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     customer_id uuid;
     customer_row myenergy.customers;
     new_status "myenergy"."customer_status_enum";
BEGIN
    IF OLD.signed_date is null AND NEW.signed_date IS NOT NULL THEN
        SELECT "customer" FROM "myenergy"."customer_accounts" WHERE account IN (
            SELECT id FROM myenergy.accounts WHERE current_contract = NEW.id
        )
        INTO customer_id;
        
        SELECT * FROM "myenergy"."customers" WHERE id = customer_id INTO customer_row;
        
        -- Pass current status as old_status
        SELECT myenergy.customer_status(customer_row, customer_row.status, NULL) INTO new_status;
        UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;
    END IF;
    RETURN NEW;
END;
$$;

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

-- recreate this trigger as a deferred trigger so that contract signed updates
-- are committed when it executes. otherwise customer_status sees unsigned 
-- contracts.

DROP TRIGGER contracts_signed_date_update_trigger ON myenergy.contracts;

CREATE CONSTRAINT TRIGGER contracts_signed_date_update_trigger 
    AFTER UPDATE OF signed_date ON myenergy.contracts
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW 
    EXECUTE FUNCTION myenergy.contracts_signed_update_customer_status();

-- tweak related to change in client.py:
--  - threshold_mask and threshold_values are no longer arrays so just removed the surrounding '[' and ']'

CREATE OR REPLACE FUNCTION myenergy.meters_with_incorrect_threshold_settings()
 RETURNS text[]
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
	RETURN (
	    SELECT array_agg(r.serial)
	    FROM flows.meter_shadows s, flows.meter_registry r
	    WHERE s.id = r.id
	    AND NOT (
	        s.tariffs_active @> '{"threshold_mask": {"rate1": false, "rate2": false, "rate3": false, "rate4": false, "rate5": false, "rate6": false, "rate7": false, "rate8": false}}'
	    AND
	        s.tariffs_active @> '{"threshold_values": {"th1": 0, "th2": 0, "th3": 0, "th4": 0, "th5": 0, "th6": 0, "th7": 0}}'
	    )
	);
END;
$function$
;

DROP VIEW myenergy.meters_with_incorrect_tariffs;

CREATE OR REPLACE VIEW myenergy.meters_with_incorrect_tariffs
WITH(security_invoker=on)
AS SELECT t.serial,
    t.unit_rate AS expected_unit_rate,
    t.standing_charge AS expected_standing_charge,
    (s.tariffs_active ->> 'unit_rate_element_a'::text)::numeric AS actual_unit_rate_a,
    (s.tariffs_active ->> 'unit_rate_element_b'::text)::numeric AS actual_unit_rate_b,
    (s.tariffs_active ->> 'standing_charge'::text)::numeric AS actual_standing_charge
   FROM myenergy.meter_tariffs t,
    flows.meter_shadows s,
    flows.meter_registry r
  WHERE t.serial = r.serial AND s.id = r.id AND t.period_start = (( SELECT max(td.period_start) AS max
           FROM myenergy.meter_tariffs td
          WHERE td.period_start < now() AND td.serial = t.serial)) AND (((s.tariffs_active ->> 'unit_rate_element_a'::text)::numeric) <> t.unit_rate OR ((s.tariffs_active ->> 'unit_rate_element_b'::text)::numeric) <> t.unit_rate OR ((s.tariffs_active ->> 'standing_charge'::text)::numeric) <> t.standing_charge);

COMMIT;
