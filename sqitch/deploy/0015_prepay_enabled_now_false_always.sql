-- Deploy supabase:0015_prepay_enabled_now_false_always to pg

BEGIN;


--
-- The only change in this function is the prelive check clause:
--
--               AND (m.prepay_enabled IS NULL OR m.prepay_enabled = false)
--
-- changes to
--
--               AND (m.prepay_enabled IS NULL)
-- 
-- because we are setting prepay_enabled false for all meters now.
--

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
            AND (m.prepay_enabled IS NULL)
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


--
-- Removed clause "mr.prepay_enabled is true and" from the view:
--

CREATE OR REPLACE VIEW flows.meters_low_balance as 
    select mr.id, mr.serial, mr.name, ms.balance
    from flows.meter_shadows ms, flows.meter_registry mr
    where ms.id = mr.id and 
    ms.balance < 15.0;


COMMIT;
