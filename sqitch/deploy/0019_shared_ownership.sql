-- Deploy supabase:0019_shared_ownership to pg
-- Shared ownership: corporate_bodies tables, auth.users triggers, corporate body customer status

BEGIN;

-- Create corporate_bodies table
CREATE TABLE myenergy.corporate_bodies (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    CONSTRAINT corporate_bodies_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE myenergy.corporate_bodies IS 'Corporate bodies that are shared owners of properties (e.g. Bridport Cohousing)';

-- Create customer_corporate_bodies table
CREATE TABLE myenergy.customer_corporate_bodies (
    customer uuid NOT NULL,
    corporate_body uuid NOT NULL,
    CONSTRAINT customer_corporate_bodies_pkey PRIMARY KEY (customer, corporate_body),
    CONSTRAINT customer_corporate_bodies_customer_fkey FOREIGN KEY (customer) REFERENCES myenergy.customers(id),
    CONSTRAINT customer_corporate_bodies_corporate_body_fkey FOREIGN KEY (corporate_body) REFERENCES myenergy.corporate_bodies(id)
);

COMMENT ON TABLE myenergy.customer_corporate_bodies IS 'Joins corporate body members (customers) to corporate bodies for shared ownership schemes';

-- Create registered_proprietors table
CREATE TABLE myenergy.registered_proprietors (
    property uuid NOT NULL REFERENCES myenergy.properties(id),
    customer uuid NOT NULL REFERENCES myenergy.customers(id),
    tenure_type text NOT NULL CHECK (tenure_type IN ('joint_tenant', 'tenant_in_common')),
    CONSTRAINT registered_proprietors_pkey PRIMARY KEY (property, customer)
);

COMMENT ON TABLE myenergy.registered_proprietors IS 'Stores registered proprietors (owners) of properties';

COMMENT ON COLUMN myenergy.properties.owner IS 'deprecated: to be removed in future';

CREATE OR REPLACE FUNCTION myenergy.migrate_property_owners_to_registered_proprietors()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    row_count integer;
BEGIN
    INSERT INTO myenergy.registered_proprietors (property, customer, tenure_type)
    SELECT id, owner, 'joint_tenant'::text
    FROM myenergy.properties
    WHERE owner IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM myenergy.registered_proprietors rp
          WHERE rp.property = properties.id
      );

    GET DIAGNOSTICS row_count = ROW_COUNT;
    RETURN row_count;
END;
$$;

-- auth.users triggers (moved from supabase-host sqitch)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_customers_on_email_update_trigger') THEN
    CREATE TRIGGER update_customers_on_email_update_trigger
      AFTER UPDATE OF email ON auth.users
      FOR EACH ROW EXECUTE FUNCTION myenergy.customer_email_update_for_trigger();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'customer_registration_trigger') THEN
    CREATE TRIGGER customer_registration_trigger
      BEFORE INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION myenergy.customer_registration();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'customer_status_auth_users_update') THEN
    CREATE TRIGGER customer_status_auth_users_update
      AFTER UPDATE ON auth.users
      FOR EACH ROW EXECUTE FUNCTION myenergy.customer_status_update_on_auth_users_trigger();
  END IF;
END $$;

-- Corporate body members become live once they have an auth.users entry.
-- Also fixes: trigger now passes NULL for old_status so deliberate flag
-- toggles (has_payment_method etc.) correctly recompute status from scratch.
-- Also fixes: prelive check uses IS NOT TRUE so explicit false counts as unprepared.
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

COMMIT;
