CREATE SCHEMA IF NOT EXISTS flows;

CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit with schema "extensions";

-- required to allow authenticator to switch into role flows
-- without this we will see 'permission denied to set role "public_backend"' from postgREST
-- see https://supabase.com/docs/guides/database/postgres/roles#authenticator
GRANT flows to authenticator;

ALTER ROLE grafanareader SET search_path = public,flows;

-- CREATE ROLE public_backend WITH bypassrls;

-- GRANT USAGE ON SCHEMA public TO public_backend;

-- -- required to allow authenticator to switch into role public_backend
-- -- without this we will see 'permission denied to set role "public_backend"' from postgREST
-- -- see https://supabase.com/docs/guides/database/postgres/roles#authenticator
-- GRANT public_backend to authenticator;

-- --
-- -- pg_graphql privs required for public_backend: 
-- --

-- grant usage on schema graphql_public to public_backend;
-- grant usage on schema graphql to public_backend;

-- alter default privileges in schema graphql_public grant all on functions to public_backend;
-- alter default privileges in schema graphql grant all on functions to public_backend;

-- COMMENT ON SCHEMA public IS '@graphql({"max_rows": 100})';


CREATE TYPE public.account_event_type_enum AS ENUM (
    'open',
    'close',
    'friendly_start',
    'friendly_end'
);


ALTER TYPE public.account_event_type_enum OWNER TO postgres;


CREATE TYPE public.account_role_type_enum AS ENUM (
    'owner',
    'occupier'
);


ALTER TYPE public.account_role_type_enum OWNER TO postgres;


CREATE TYPE public.account_status_enum AS ENUM (
    'open',
    'closed',
    'pending'
);


ALTER TYPE public.account_status_enum OWNER TO postgres;


CREATE TYPE public.account_type_enum AS ENUM (
    'supply',
    'solar',
    'ev'
);


ALTER TYPE public.account_type_enum OWNER TO postgres;


CREATE TYPE public.circuit_type_enum AS ENUM (
    'heat',
    'power',
    'solar'
);


ALTER TYPE public.circuit_type_enum OWNER TO postgres;


CREATE TYPE public.contract_subtype_enum AS ENUM (
    'thirty_year',
    'short_term'
);


ALTER TYPE public.contract_subtype_enum OWNER TO postgres;


CREATE TYPE public.contract_type_enum AS ENUM (
    'supply',
    'solar',
    'ev'
);


ALTER TYPE public.contract_type_enum OWNER TO postgres;


CREATE TYPE public.customer_invite_status_enum AS ENUM (
    'pending',
    'expired'
);


ALTER TYPE public.customer_invite_status_enum OWNER TO postgres;


CREATE TYPE public.customer_status_enum AS ENUM (
    'pending',
    'live',
    'archived',
    'preonboarding',
    'onboarding',
    'prelive',
    'exiting'
);


ALTER TYPE public.customer_status_enum OWNER TO postgres;


CREATE TYPE public.monthly_costs_compute_query_result_row_type AS (
	circuit_id uuid,
	kwh numeric,
	customer uuid,
	type public.circuit_type_enum,
	esco_code text,
	region text
);


ALTER TYPE public.monthly_costs_compute_query_result_row_type OWNER TO postgres;


CREATE TYPE public.payment_status_enum AS ENUM (
    'created',
    'pending',
    'processing',
    'cancelled',
    'failed',
    'succeeded'
);


ALTER TYPE public.payment_status_enum OWNER TO postgres;


CREATE TYPE public.property_tenure_enum AS ENUM (
    'separate_owner_and_occupier',
    'single_owner_occupier',
    'shared_ownership'
);


ALTER TYPE public.property_tenure_enum OWNER TO postgres;


CREATE TYPE public.topup_event_enum AS ENUM (
    'initialised',
    'generate_failure',
    'generate_succeeded',
    'meter_send_failure',
    'meter_send_succeeded'
);


ALTER TYPE public.topup_event_enum OWNER TO postgres;


CREATE TYPE public.topup_source_enum AS ENUM (
    'payment',
    'gift',
    'solar_credit',
    'adjustment'
);


ALTER TYPE public.topup_source_enum OWNER TO postgres;


CREATE TYPE public.topup_status_enum AS ENUM (
    'wait_token_fetch',
    'failed_token_fetch',
    'wait_token_push',
    'failed_token_push',
    'completed',
    'pending'
);


ALTER TYPE public.topup_status_enum OWNER TO postgres;


CREATE FUNCTION flows.get_meters_for_cli(esco_filter text, feeder_filter text) RETURNS TABLE(id uuid, ip_address text, serial text, name text, esco text, csq integer, health text, hardware text, feeder text)
    LANGUAGE plpgsql
    AS $$
	BEGIN
		RETURN QUERY
		SELECT 
			mr.id as id, host(mr.ip_address) as ip_address,
			mr.serial as serial,
			mr.name as name, 
			e.code as esco,
			ms.csq as csq,
			ms.health::text as health,
			mr.hardware as hardware,
			fr."name" 
		FROM 
			flows.meter_registry mr
			JOIN flows.meter_shadows ms ON mr.id = ms.id
			LEFT JOIN flows.escos e ON mr.esco = e.id
			LEFT JOIN flows.service_head_meter shm ON mr.id = shm.meter
			LEFT JOIN flows.service_head_registry shr ON shr.id = shm.service_head
			LEFT JOIN flows.feeder_registry fr ON shr.feeder = fr.id
		WHERE 
			(esco_filter is null OR e.code = esco_filter) AND
			mr.mode = 'active' AND
			(feeder_filter is null OR fr.name = feeder_filter OR (feeder_filter = 'null' AND shr.feeder IS NULL));
	END;
	$$;


ALTER FUNCTION flows.get_meters_for_cli(esco_filter text, feeder_filter text) OWNER TO postgres;


create type flows.market_data_input as (time timestamptz, type integer, value float4);

CREATE FUNCTION flows.insert_market_data_batch(data flows.market_data_input[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    last_value FLOAT;
    data_record flows.market_data_input;
    epsilon FLOAT := 1e-6;  -- Define a small threshold for "nearly equal"
BEGIN
     -- Loop through each row in the input array
    FOREACH data_record IN ARRAY data LOOP

        -- Get the last inserted value (most recent)
        SELECT value INTO last_value
	    FROM flows.market_data
	    WHERE type = data_record.type and time = data_record.time
	    ORDER BY created_at DESC
	    LIMIT 1;

	    -- If the table is empty or the value has changed, insert the new row
        IF last_value IS NULL OR ABS(last_value - data_record.value) > epsilon THEN
            INSERT INTO flows.market_data (time, type, value)
            VALUES (data_record.time, data_record.type, data_record.value);
        END IF;
    END LOOP;
END;
$$;

ALTER FUNCTION flows.insert_market_data_batch(data flows.market_data_input[]) OWNER TO postgres;


CREATE FUNCTION flows.sync_flows_to_public_meters() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    WITH data AS (
        SELECT r.id, r.serial, s.balance, r.prepay_enabled
        FROM flows.meter_registry r
        JOIN flows.meter_shadows s ON r.id = s.id
    )
    UPDATE public.meters m
        SET balance = data.balance,
            prepay_enabled = data.prepay_enabled
        FROM data
        WHERE m.serial = data.serial;
END;
$$;


ALTER FUNCTION flows.sync_flows_to_public_meters() OWNER TO postgres;


CREATE FUNCTION public.account_check_contract_terms_and_esco() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    esco_id uuid;
    terms_id uuid;
BEGIN
    SELECT esco FROM public.properties WHERE id = NEW.property
        INTO esco_id; 
    SELECT terms FROM public.contracts WHERE id = NEW.current_contract
        INTO terms_id;

    IF terms_id is null THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.contract_terms_esco
        WHERE esco = esco_id
        AND terms = terms_id
    ) THEN
        RAISE EXCEPTION 'Contract terms for the contract being added are not allowed for the esco this account is part of';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.account_check_contract_terms_and_esco() OWNER TO postgres;



CREATE TABLE public.customer_accounts (
    customer uuid NOT NULL,
    account uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    role public.account_role_type_enum NOT NULL,
    notes text
);


ALTER TABLE public.customer_accounts OWNER TO postgres;



CREATE TABLE public.escos (
    id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    name text,
    code text,
    app_url text,
    region text
);


ALTER TABLE public.escos OWNER TO postgres;


CREATE TABLE public.meters (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    serial text,
    wallet uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    prepay_enabled boolean,
    balance numeric
);


ALTER TABLE public.meters OWNER TO postgres;


CREATE TABLE public.properties (
    created_at timestamp with time zone DEFAULT now(),
    plot text,
    site uuid,
    description text,
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    solar_meter uuid,
    supply_meter uuid,
    owner uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    esco uuid,
    tenure public.property_tenure_enum DEFAULT 'single_owner_occupier'::public.property_tenure_enum
);


ALTER TABLE public.properties OWNER TO postgres;


COMMENT ON COLUMN public.properties.tenure IS 'Indicates the property tenure type: separate_owner_and_occupier, single_owner_occupier, or shared_ownership';



CREATE TABLE public.customers (
    fullname text,
    email text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    exiting boolean DEFAULT false NOT NULL,
    status public.customer_status_enum DEFAULT 'pending'::public.customer_status_enum NOT NULL,
    cepro_user boolean DEFAULT false NOT NULL,
    confirmed_details_at timestamp with time zone,
    allow_onboard_transition boolean DEFAULT false NOT NULL,
    has_payment_method boolean DEFAULT false NOT NULL
);


ALTER TABLE public.customers OWNER TO postgres;


COMMENT ON COLUMN public.customers.exiting IS 'An operator can set this flag to true when a customer wants to exit cepro as supplier. This will result in the customer status updating to ''exiting'' also.';



COMMENT ON COLUMN public.customers.allow_onboard_transition IS 'Is manually configured gate that for early testing phases allows us to individually select which users can progress to onboarding and then live status.';



COMMENT ON COLUMN public.customers.has_payment_method IS 'The customer has setup a payment method in Stripe.

The accounts service is notified when a payment method is added and it will update this flag.';


CREATE FUNCTION public.customer() RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
        select id
        FROM public.customers
        where email = auth.email();
$$;


ALTER FUNCTION public.customer() OWNER TO postgres;


GRANT ALL ON FUNCTION public.customer() TO anon;
GRANT ALL ON FUNCTION public.customer() TO authenticated;
GRANT ALL ON FUNCTION public.customer() TO service_role;



CREATE FUNCTION public.accounts() RETURNS uuid[]
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
        SELECT array_agg(account)
        FROM   public.customer_accounts
        WHERE  customer = public.customer();
$$;


ALTER FUNCTION public.accounts() OWNER TO postgres;



CREATE FUNCTION public.customer_status(new_customer_row public.customers) RETURNS public.customer_status_enum
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    auth_user_email_count int;
    contract_count int;
    signed_contract_count int;
    has_unprepared_supply_meter boolean;
BEGIN
    -- cepro admin's are always live
    IF new_customer_row.cepro_user IS true THEN
        RETURN 'live'::public.customer_status_enum;
    END IF;

    -- exiting - flag explicitly set
    IF new_customer_row.exiting IS true THEN
        RETURN 'exiting'::public.customer_status_enum;
    END IF;

    -- pending - not yet registered from app sign up form
    SELECT count(*) FROM auth.users WHERE "email" = new_customer_row.email INTO auth_user_email_count;
    IF auth_user_email_count = 0 THEN
        RETURN 'pending'::public.customer_status_enum;
    END IF;

    -- pre-onboarding - flag blocks transition to onboarding
    IF new_customer_row.allow_onboard_transition IS NOT TRUE THEN
        RETURN 'preonboarding'::public.customer_status_enum;
    END IF;

    -- pre-onboarding - registered but contract records to sign
    SELECT count(*) FROM public.accounts a
    JOIN public.customer_accounts ca ON ca.account = a.id 
    LEFT JOIN public.contracts c ON c.id = a.current_contract
    WHERE a.current_contract is not null
    AND ca.customer = new_customer_row.id
    AND NOT (
        (ca.role = 'owner' AND (c.type = 'supply' OR a.type = 'supply'))
        OR 
        (ca.role = 'occupier' AND (c.type = 'solar' OR a.type = 'solar'))
    )
    INTO contract_count;
    -- RAISE NOTICE 'signable_contract_count %', contract_count;
    IF contract_count = 0 THEN
        RETURN 'preonboarding'::public.customer_status_enum;
    END IF;

    -- get count of contracts signed by this customer
    SELECT count(*) FROM public.accounts a
    JOIN public.customer_accounts ca ON ca.account = a.id 
    LEFT JOIN public.contracts c ON c.id = a.current_contract
    WHERE ca.customer = new_customer_row.id
    AND a.current_contract IN (
        SELECT id from public.contracts where signed_date is NOT null
    )
    AND NOT (
        (ca.role = 'owner' AND (c.type = 'supply' OR a.type = 'supply'))
        OR 
        (ca.role = 'occupier' AND (c.type = 'solar' OR a.type = 'solar'))
    )
    INTO signed_contract_count;
    -- RAISE NOTICE 'signed_contract_count %', signed_contract_count;

    -- onboarding - contracts exist but not all signed
    IF
        signed_contract_count != contract_count or
        new_customer_row.confirmed_details_at is null or
        new_customer_row.has_payment_method is not true
    THEN
        RETURN 'onboarding'::public.customer_status_enum;
    END IF;
    
    -- Check if this customer is an occupier on any supply account with unprepared meter
    SELECT EXISTS (
        SELECT 1 FROM public.customer_accounts ca
        JOIN public.accounts a ON a.id = ca.account
        JOIN public.properties p ON p.id = a.property
        JOIN public.meters m ON m.id = p.supply_meter
        WHERE ca.customer = new_customer_row.id
        AND ca.role = 'occupier'
        AND a.type = 'supply'
        AND (m.prepay_enabled IS NULL OR m.prepay_enabled = false)
    ) INTO has_unprepared_supply_meter;
    
    -- prelive - all onboarding complete but supply meter not prepay_enabled
    IF has_unprepared_supply_meter THEN
        RETURN 'prelive'::public.customer_status_enum;
    END IF;

    -- live - contracts have been signed and supply meter is ready
    RETURN 'live'::public.customer_status_enum;
END;
$$;


ALTER FUNCTION public.customer_status(new_customer_row public.customers) OWNER TO postgres;


CREATE FUNCTION public.customer_status_update_on_auth_users_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    customer public.customers;
    new_status "public"."customer_status_enum";
BEGIN
    SELECT * FROM public.customers WHERE email = NEW.email INTO customer;
    IF customer IS NOT NULL THEN
        SELECT public.customer_status(customer) INTO new_status; 
        UPDATE public.customers SET status = new_status WHERE id = customer.id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.customer_status_update_on_auth_users_trigger() OWNER TO postgres;


CREATE FUNCTION public.customer_status_update_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     new_status public.customer_status_enum;
BEGIN
    SELECT public.customer_status(NEW) INTO new_status; 
    NEW.status = new_status;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.customer_status_update_on_trigger() OWNER TO postgres;



CREATE FUNCTION public.accounts_current_contract_update_customer_status_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     customer_id uuid;
     customer_row public.customers;
     new_status "public"."customer_status_enum";
BEGIN
    FOR customer_id IN 
        SELECT "customer" 
        FROM "public"."customer_accounts" 
        WHERE account = NEW.id
    LOOP
        -- Get customer record
        SELECT * FROM "public"."customers" 
        WHERE id = customer_id 
        INTO customer_row;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer not found with ID: %', customer_id;
        END IF;
        
        -- Calculate and update new status
        SELECT public.customer_status(customer_row) INTO new_status;
        RAISE NOTICE 'New status % for customer %', new_status, customer_id;
        
		UPDATE public.customers SET status = new_status WHERE id = customer_id;
        
        RAISE NOTICE 'Updated status for customer: %', customer_id;
    END LOOP;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.accounts_current_contract_update_customer_status_trigger() OWNER TO postgres;


CREATE FUNCTION public.accounts_generate_name_for_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    property_str text;
    esco_str text;
BEGIN
	SELECT p.plot, e.code 
		FROM public.properties p, public.escos e
		WHERE p.id = NEW.property AND p.esco = e.id
	INTO property_str, esco_str;

    UPDATE public.accounts
		SET name = (NEW.type || '-' || esco_str || '-' || property_str)
		WHERE id = NEW.id;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.accounts_generate_name_for_trigger() OWNER TO postgres;


CREATE FUNCTION public.add_account(account_type public.account_type_enum, property_id uuid, owner_id uuid, occupier_id uuid, contract_terms_id uuid, no_contract boolean) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    account_id uuid;
    contract_id uuid;
    is_owner_occupied boolean;
BEGIN
    -- Create the account
    INSERT INTO public.accounts (property, "status", "type") 
        VALUES (property_id, 'pending', account_type)
        RETURNING id INTO account_id;

    -- Determine if property is owner occupied
    is_owner_occupied := (owner_id = occupier_id);

    -- Create customer_accounts records
    IF account_type = 'solar' THEN
        -- Solar account - owner is always the primary
        INSERT INTO public.customer_accounts (customer, account, role)
            VALUES (owner_id, account_id, 'owner');
            
        -- For non-owner-occupied properties, add occupier record for solar
        IF NOT is_owner_occupied THEN
            INSERT INTO public.customer_accounts (customer, account, role)
                VALUES (occupier_id, account_id, 'occupier');
        END IF;
    ELSE -- Supply account
        -- For supply, occupier is primary
        INSERT INTO public.customer_accounts (customer, account, role)
            VALUES (occupier_id, account_id, 'occupier');
            
        -- For non-owner-occupied properties, add owner record for supply
        IF NOT is_owner_occupied THEN
            INSERT INTO public.customer_accounts (customer, account, role)
                VALUES (owner_id, account_id, 'owner');
        END IF;
    END IF;

    -- Create contract if needed
    IF no_contract is false THEN
        INSERT INTO public.contracts (terms, "type")
            VALUES (contract_terms_id, account_type::text::contract_type_enum)
            RETURNING id INTO contract_id;

        UPDATE public.accounts
            SET current_contract = contract_id,
                "status" = 'open'
            WHERE id = account_id;
    END IF;

    RETURN account_id;
END;
$$;


ALTER FUNCTION public.add_account(account_type public.account_type_enum, property_id uuid, owner_id uuid, occupier_id uuid, contract_terms_id uuid, no_contract boolean) OWNER TO postgres;


CREATE FUNCTION public.add_account(account_type public.account_type_enum, property_id uuid, customer_id uuid, account_role public.account_role_type_enum, contract_terms_id uuid, no_contract boolean) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
  declare
  account_id uuid;
  contract_id uuid;
BEGIN
  INSERT INTO public.accounts (property, "status", "type") 
    VALUES (property_id, 'pending', account_type)
    RETURNING id INTO account_id;
  
  INSERT INTO public.customer_accounts (customer, account, role)
    VALUES (customer_id, account_id, account_role);
  
  IF no_contract is false THEN
      INSERT INTO public.contracts (terms, "type")
        VALUES (contract_terms_id, account_type::text::contract_type_enum)
        RETURNING id INTO contract_id;

      UPDATE public.accounts
        SET current_contract = contract_id, "status" = 'open'
        WHERE id = account_id;
  END IF;

  RETURN account_id;
END;
$$;


ALTER FUNCTION public.add_account(account_type public.account_type_enum, property_id uuid, customer_id uuid, account_role public.account_role_type_enum, contract_terms_id uuid, no_contract boolean) OWNER TO postgres;


CREATE FUNCTION public.add_meter(property_id uuid, serial text, is_supply boolean) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
  declare
  meter_id uuid;
  wallet_id uuid;
BEGIN
  IF is_supply THEN
    INSERT INTO public.wallets(balance) VALUES (0)
      RETURNING id INTO wallet_id;
  END IF;

  INSERT INTO public.meters (serial, wallet) VALUES (
        serial, wallet_id)
    RETURNING id INTO meter_id;
  
  -- Property meter reference - for now derive the column from the type of register_a
  IF is_supply THEN
    UPDATE public.properties SET supply_meter = meter_id where id = property_id;
  ELSE
    UPDATE public.properties SET solar_meter = meter_id where id = property_id;
  END IF;

  RETURN meter_id;
END;
$$;


ALTER FUNCTION public.add_meter(property_id uuid, serial text, is_supply boolean) OWNER TO postgres;


CREATE FUNCTION public.add_property(plot_number text, esco_id uuid, solar_meter_serial text, supply_meter_serial text, description text, is_owner_occupied boolean, preonboard_only boolean) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    plot_name text := 'plot' || plot_number;
    esco_code text := (select code from public.escos where id = esco_id); 
    property_id uuid := extensions.uuid_generate_v4();
    owner_id uuid := extensions.uuid_generate_v4();
    occupier_id uuid := extensions.uuid_generate_v4();
    solar_meter_id uuid;
    solar_account_id uuid;
    supply_meter_id uuid;
    supply_account_id uuid;
    supply_contract_terms_id uuid;
BEGIN
    -- Create owner customer
    INSERT INTO public.customers (fullname, email, id) 
        VALUES (plot_name || ' Owner', plot_name || 'owner-' || esco_code || '@change.me', owner_id);

    -- Create occupier customer (if not owner occupied)
    IF is_owner_occupied = false THEN
        INSERT INTO public.customers (fullname, email, id) 
            VALUES (plot_name || ' occupier', plot_name || 'occupier-' || esco_code || '@change.me', occupier_id);
    ELSE
        occupier_id := owner_id;
    END IF;

    -- Create property
    INSERT INTO public.properties (plot, description, owner, esco, id)
        VALUES (
            'Plot-' || plot_number,
            description,
            owner_id,
            esco_id,
            property_id
        );

    -- Handle solar installation if meter provided
    IF solar_meter_serial is not null THEN
        -- Create solar meter
        SELECT public.add_meter(
            property_id, solar_meter_serial, false
        ) INTO solar_meter_id;

        -- Create solar account
        SELECT public.add_account(
            'solar'::account_type_enum,
            property_id,
            owner_id,
            occupier_id,
            null,  -- solar contract terms - owner will choose which contract terms
            preonboard_only  -- no_contract == true when preonboard
        ) INTO solar_account_id;
    END IF;

    -- Create supply meter
    SELECT public.add_meter(
        property_id, supply_meter_serial, true
    ) INTO supply_meter_id;

    -- Get latest supply contract terms
    WITH latest_supply_terms_by_esco AS (
        select cte.terms, ct.version 
        from contract_terms ct, contract_terms_esco cte
        where cte.esco = esco_id
        and cte.terms = ct.id
        and ct."type" = 'supply'
        order by version desc
        limit 1
    ) SELECT terms FROM latest_supply_terms_by_esco INTO supply_contract_terms_id;

    -- Create supply account
    SELECT public.add_account(
        'supply'::account_type_enum,
        property_id,
        owner_id,
        occupier_id,
        supply_contract_terms_id,
        preonboard_only  -- no_contract == true when preonboard
    ) INTO supply_account_id;

    RETURN 'property: ' || property_id || 
        ' supply account: ' || supply_account_id ||
        ' supply meter: ' || supply_meter_id ||
        ' solar account: ' || solar_account_id ||
        ' solar meter: ' || solar_meter_id;
END;
$$;


ALTER FUNCTION public.add_property(plot_number text, esco_id uuid, solar_meter_serial text, supply_meter_serial text, description text, is_owner_occupied boolean, preonboard_only boolean) OWNER TO postgres;


CREATE FUNCTION public.auth_user_id_for_customer(email text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT jsonb_build_object(
        'id', (SELECT to_jsonb(u.id) FROM auth.users u WHERE u.email = auth_user_id_for_customer."email"),
        'phone', (SELECT to_jsonb(u.phone) FROM auth.users u WHERE u.email = auth_user_id_for_customer."email")
    );
$$;


ALTER FUNCTION public.auth_user_id_for_customer(email text) OWNER TO postgres;


CREATE FUNCTION public.benchmark_month_standing_charge(region_in text, month_in date) RETURNS numeric
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
    benchmark_standing_charge numeric;
  num_days int4;
BEGIN
  SELECT standing_charge
  FROM public.benchmark_tariffs
  WHERE period_start <= month_in
    AND region = region_in
  ORDER BY period_start desc
  LIMIT 1
    INTO benchmark_standing_charge;

  SELECT public.days_in_month(month_in)
    INTO num_days;
  
  RETURN benchmark_standing_charge * num_days;
END;
$$;


ALTER FUNCTION public.benchmark_month_standing_charge(region_in text, month_in date) OWNER TO postgres;


CREATE FUNCTION public.benchmark_tariffs_generate_tariffs() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
    -- Call the function to generate customer and microgrid tariffs
    -- using the period_start date from the inserted/updated benchmark tariff
    PERFORM public.generate_new_quarter_tariffs(NEW.period_start);
    
    -- Log the action
    RAISE NOTICE 'Generated customer and microgrid tariffs for period starting %', NEW.period_start;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.benchmark_tariffs_generate_tariffs() OWNER TO postgres;


COMMENT ON FUNCTION public.benchmark_tariffs_generate_tariffs() IS 'Trigger function that calls generate_customer_tariffs_new_quarter when a benchmark tariff is inserted or updated.
This ensures that customer and microgrid tariffs are automatically updated when benchmark tariffs change.';



CREATE FUNCTION public.benchmark_unit_rate(region_in text, month_in date) RETURNS numeric
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  rate numeric;
BEGIN
  SELECT unit_rate
  FROM public.benchmark_tariffs
  WHERE period_start <= month_in
    AND region = region_in
  ORDER BY period_start desc
  LIMIT 1
    INTO rate;

  RETURN rate;
END;
$$;


ALTER FUNCTION public.benchmark_unit_rate(region_in text, month_in date) OWNER TO postgres;


CREATE FUNCTION public.change_property_owner(property_id uuid, new_owner uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    update public.properties
    set owner = new_owner
    where id = property_id;

    -- TODO: in test this fine but eventually this should close the existing 
    --       account and create a new one for the new owner    
    update public.customer_accounts
    set customer = new_owner
    where account IN (SELECT id from accounts WHERE property = property_id)
    and role = 'owner';
END;
$$;


ALTER FUNCTION public.change_property_owner(property_id uuid, new_owner uuid) OWNER TO postgres;


CREATE FUNCTION public.check_property_setup(property_id uuid) RETURNS SETOF text
    LANGUAGE plpgsql
    AS $$
DECLARE
    supply_meter_id uuid;
    solar_meter_id uuid;
BEGIN
    SELECT supply_meter, solar_meter INTO supply_meter_id, solar_meter_id 
    FROM properties
    WHERE "id" = property_id;

    IF supply_meter_id is null THEN
        RETURN NEXT 'No supply meter is defined on the property . Is it expected?';
    ELSE 
        RETURN NEXT 'Supply meter ' || supply_meter_id || ' defined on property';
    END IF;

    IF solar_meter_id is null THEN
        RETURN NEXT 'No solar meter is defined on the property . Is it expected?';
    ELSE 
        RETURN NEXT 'Solar meter ' || solar_meter_id || ' defined on property';
    END IF;
END;
$$;


ALTER FUNCTION public.check_property_setup(property_id uuid) OWNER TO postgres;


CREATE FUNCTION public.check_unique_properties_meters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (
    SELECT COUNT(*)
    FROM public.properties p
    WHERE supply_meter = NEW.solar_meter
      OR solar_meter = NEW.supply_meter
      OR new.supply_meter = NEW.solar_meter
  ) > 0 THEN
    RAISE EXCEPTION 'A single meter must be unique across the columns supply_meter and solar_meter.';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_unique_properties_meters() OWNER TO postgres;



CREATE TABLE public.circuit_meter (
    circuit_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.circuit_meter OWNER TO postgres;


CREATE TABLE public.circuits (
    id uuid NOT NULL,
    type public.circuit_type_enum NOT NULL,
    name text,
    created_at timestamp with time zone
);


ALTER TABLE public.circuits OWNER TO postgres;


CREATE TABLE public.contract_terms_esco (
    esco uuid,
    terms uuid
);


ALTER TABLE public.contract_terms_esco OWNER TO postgres;


CREATE TABLE public.customer_events (
    customer uuid NOT NULL,
    event_type text NOT NULL,
    data jsonb,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);


ALTER TABLE public.customer_events OWNER TO postgres;



CREATE FUNCTION public.customer_invites_status(accessed_at timestamp with time zone, expires_at timestamp with time zone) RETURNS public.customer_invite_status_enum
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF accessed_at is not null OR expires_at < now() THEN 
        RETURN 'expired'::customer_invite_status_enum;
    ELSE
        RETURN 'pending'::customer_invite_status_enum;
    END IF;
END;
$$;


ALTER FUNCTION public.customer_invites_status(accessed_at timestamp with time zone, expires_at timestamp with time zone) OWNER TO postgres;



CREATE TABLE public.customer_invites (
    invite_token uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    customer uuid NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    accessed_at timestamp with time zone,
    invite_url text,
    status public.customer_invite_status_enum GENERATED ALWAYS AS (public.customer_invites_status(accessed_at, expires_at)) STORED NOT NULL
);


ALTER TABLE public.customer_invites OWNER TO postgres;


COMMENT ON COLUMN public.customer_invites.accessed_at IS 'Set to the timestamp the invite was accessed at /customer/invite/<backend>. This immediately expires the token.';



CREATE SEQUENCE public.account_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.account_number_seq OWNER TO postgres;


CREATE TABLE public.accounts (
    account_number bigint DEFAULT nextval('public.account_number_seq'::regclass) NOT NULL,
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    property uuid NOT NULL,
    current_contract uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    type public.account_type_enum,
    status public.account_status_enum,
    end_date timestamp with time zone,
    name text
);


ALTER TABLE public.accounts OWNER TO postgres;


COMMENT ON COLUMN public.accounts.name IS 'Human readable name of the account generated from triggers';



CREATE TABLE public.contracts (
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    end_date date,
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    effective_date date,
    signed_date date,
    terms uuid,
    type public.contract_type_enum,
    docuseal_submission_id integer,
    signed_contract_url text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.contracts OWNER TO postgres;


COMMENT ON COLUMN public.contracts.type IS 'Also in the terms but required here as initially terms may not be associated with the contract. The customer will choose which terms later.';



COMMENT ON COLUMN public.contracts.docuseal_submission_id IS 'ID in docuseal of the "submission" which is a signed instance of a template contract.';



COMMENT ON COLUMN public.contracts.signed_contract_url IS 'URL to the signed PDF which is a secret but unprotected URL to docuseal servers.';



CREATE FUNCTION public.properties_by_account() RETURNS uuid[]
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT array_agg(a.property)::uuid[]
    FROM   public.accounts a, public.customer_accounts ca
    WHERE  ca.customer = public.customer()
    AND    a.id = ca.account
$$;


ALTER FUNCTION public.properties_by_account() OWNER TO postgres;


CREATE FUNCTION public.properties_owned() RETURNS uuid[]
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT array_agg(p.id)::uuid[]
    FROM public.properties p
    WHERE p.owner = public.customer()
$$;


ALTER FUNCTION public.properties_owned() OWNER TO postgres;



CREATE FUNCTION public.circuits() RETURNS uuid[]
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT array_agg(cm.circuit_id)::uuid[]
    FROM   public.properties p, public.circuit_meter cm
    WHERE  p.id = ANY(public.properties_by_account())
    AND    cm.meter_id in (p.solar_meter, p.supply_meter)
$$;


ALTER FUNCTION public.circuits() OWNER TO postgres;


CREATE FUNCTION public.contract_check_contract_terms_and_esco() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    account_id uuid;
    esco_id uuid;
    terms_id uuid;
BEGIN
    SELECT id FROM public.accounts WHERE current_contract = NEW.id
        INTO account_id;
    SELECT esco FROM public.properties WHERE id in (
        SELECT property FROM public.accounts WHERE id = account_id
    ) INTO esco_id; 
    SELECT terms FROM public.contracts WHERE id = NEW.id
        INTO terms_id;

    IF NOT EXISTS (
        SELECT 1
        FROM public.contract_terms_esco
        WHERE esco = esco_id
        AND terms = terms_id
    ) THEN
        RAISE EXCEPTION 'Contract terms are not valid for the ESCO associated with this contract and account';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.contract_check_contract_terms_and_esco() OWNER TO postgres;


CREATE FUNCTION public.contracts_signed_update_customer_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     customer_id uuid;
     customer_row public.customers;
     new_status "public"."customer_status_enum";
BEGIN
    IF OLD.signed_date is null AND NEW.signed_date IS NOT NULL THEN
        SELECT "customer" FROM "public"."customer_accounts" WHERE account IN (
            SELECT id FROM public.accounts WHERE current_contract = NEW.id
        )
        INTO customer_id;
        SELECT * FROM "public"."customers" WHERE id = customer_id INTO customer_row;
        SELECT public.customer_status(customer_row) INTO new_status;
        UPDATE public.customers SET status = new_status WHERE id = customer_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.contracts_signed_update_customer_status() OWNER TO postgres;


CREATE FUNCTION public.create_user(email text, password text) RETURNS void
    LANGUAGE plpgsql
    AS $$
  declare
  user_id uuid;
  encrypted_pw text;
BEGIN
  user_id := gen_random_uuid();
  encrypted_pw := extensions.crypt(password, extensions.gen_salt('bf'));
  
  INSERT INTO auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
  VALUES
    ('00000000-0000-0000-0000-000000000000', user_id, 'authenticated', 'authenticated', email, encrypted_pw, '2023-05-03 19:41:43.585805+00', '2023-04-22 13:10:03.275387+00', '2023-04-22 13:10:31.458239+00', '{"provider":"email","providers":["email"]}', '{}', '2023-05-03 19:41:43.580424+00', '2023-05-03 19:41:43.585948+00', '', '', '', '');
  
  INSERT INTO auth.identities (id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  VALUES
    (gen_random_uuid(), user_id, format('{"sub":"%s","email":"%s"}', user_id::text, email)::jsonb, 'email', '2023-05-03 19:41:43.582456+00', '2023-05-03 19:41:43.582497+00', '2023-05-03 19:41:43.582497+00');
END;
$$;


ALTER FUNCTION public.create_user(email text, password text) OWNER TO postgres;


CREATE FUNCTION public.customer_email_update_for_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    UPDATE public.customers SET email = NEW.email WHERE email = OLD.email;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.customer_email_update_for_trigger() OWNER TO postgres;


CREATE FUNCTION public.customer_invites_generate_invite_url() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        app_url text;
    BEGIN
        SELECT e.app_url
        FROM escos e
        WHERE e.id IN (
            SELECT esco FROM properties WHERE owner = NEW.customer
        ) INTO app_url;

        IF app_url is null THEN
            SELECT e.app_url
            FROM escos e
            WHERE e.id IN (
                SELECT esco FROM properties WHERE id IN (
                    SELECT property FROM accounts WHERE id IN (
                        SELECT account FROM customer_accounts WHERE customer = NEW.customer
                    )
                )
            ) INTO app_url;
        END IF;
      
        IF app_url is not null THEN
            NEW.invite_url = app_url || '/invite/' || NEW.invite_token;
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'No esco is associated with this customer yet so an invite cannot be created';
        END IF;
    END;
    $$;


ALTER FUNCTION public.customer_invites_generate_invite_url() OWNER TO postgres;


CREATE FUNCTION public.customer_invites_insert_from_customer() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.customer_invites(customer) values (new.id);
    return new;
END;
$$;


ALTER FUNCTION public.customer_invites_insert_from_customer() OWNER TO postgres;


CREATE FUNCTION public.customer_jwt_token_hook(event jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  declare
    claims jsonb;
    is_cepro_user boolean;
  begin
    -- Check if the user is marked as admin in the profiles table
    select cepro_user into is_cepro_user from public.customers
        where email in (select email from auth.users where id = (event->>'user_id')::uuid);

    if is_cepro_user then
      claims := event->'claims';

      -- Check if 'app_metadata' exists in claims
      if jsonb_typeof(claims->'app_metadata') is null then
        -- If 'app_metadata' does not exist, create an empty object
        claims := jsonb_set(claims, '{app_metadata}', '{}');
      end if;

      -- Set a claim of 'cepro_user'
      claims := jsonb_set(claims, '{app_metadata, cepro_user}', 'true');

      -- Update the 'claims' object in the original event
      event := jsonb_set(event, '{claims}', claims);
    end if;

    -- Return the modified or original event
    return event;
  end;
$$;


ALTER FUNCTION public.customer_jwt_token_hook(event jsonb) OWNER TO postgres;


CREATE FUNCTION public.customer_registration() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE email = NEW.email AND (status = 'pending' or cepro_user is true)) THEN
        RAISE EXCEPTION 'Email not setup for registration at this time: %', NEW.email;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.customer_registration() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;


CREATE FUNCTION public.customer_tariffs_compute_rates() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    benchmark_standing_charge numeric;
    benchmark_unit_rate numeric;
BEGIN
  SELECT standing_charge, unit_rate
  FROM public.benchmark_tariffs
  WHERE period_start <= NEW.period_start
  ORDER BY period_start desc
  LIMIT 1
    INTO benchmark_standing_charge, benchmark_unit_rate;
    
  NEW.computed_standing_charge = TRUNC((1 - (NEW.discount_rate_basis_points::numeric / 100)) * benchmark_standing_charge, 5);
  NEW.computed_unit_rate = TRUNC((1 - (NEW.discount_rate_basis_points::numeric / 100)) * benchmark_unit_rate, 5);

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.customer_tariffs_compute_rates() OWNER TO postgres;


CREATE FUNCTION public.customer_tariffs_create_all_for_month(month_in date, discount_rate_in integer) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
  INSERT INTO 
      public.customer_tariffs(customer, period_start, discount_rate_basis_points)
  SELECT id, month_in, discount_rate_in
      FROM public.customers
  ON CONFLICT (customer, period_start) DO UPDATE
    SET discount_rate_basis_points = EXCLUDED.discount_rate_basis_points;
END;
$$;


ALTER FUNCTION public.customer_tariffs_create_all_for_month(month_in date, discount_rate_in integer) OWNER TO postgres;


CREATE FUNCTION public.customer_update_log_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
-- DECLARE
--     column_event_pairs text[][] := ARRAY[
--         ['confirmed_details_at', 'confirmed_details'],
--         ['has_payment_method', 'payment_method']
--     ];
--     pair text[];
--     column_name text;
--     event_type public.customer_event_type_enum;
BEGIN
    -- TODO: revisit this idea of looping through pairs

    -- Loop through each column-event pair
    -- FOREACH pair SLICE 1 IN ARRAY column_event_pairs LOOP
    --     column_name := pair[1];
    --     event_type := pair[2];

    --     -- Check if the column has changed
    --     EXECUTE format('
    --         IF OLD.%I IS DISTINCT FROM NEW.%I THEN
    --             PERFORM public.log_customer_event($1, OLD, NEW);
    --         END IF;
    --     ', column_name, column_name)
    --     USING event_type;
    -- END LOOP;

    IF OLD.confirmed_details_at IS DISTINCT FROM NEW.confirmed_details_at THEN
        PERFORM public.log_customer_event('confirmed_details', OLD, NEW);
    END IF;

    IF OLD.has_payment_method IS DISTINCT FROM NEW.has_payment_method THEN
        PERFORM public.log_customer_event('payment_method', OLD, NEW);
    END IF;

    IF OLD.cepro_user IS DISTINCT FROM NEW.cepro_user THEN
        PERFORM public.log_customer_event('cepro_user', OLD, NEW);
    END IF;

    IF OLD.exiting IS DISTINCT FROM NEW.exiting THEN
        PERFORM public.log_customer_event('exiting', OLD, NEW);
    END IF;

    IF OLD.allow_onboard_transition IS DISTINCT FROM NEW.allow_onboard_transition THEN
        PERFORM public.log_customer_event('allow_onboard_transition', OLD, NEW);
    END IF;

    IF OLD.status IS DISTINCT FROM NEW.status THEN
        PERFORM public.log_customer_event('status', OLD, NEW);
    END IF;

    IF OLD.fullname IS DISTINCT FROM NEW.fullname THEN
        PERFORM public.log_customer_event('fullname', OLD, NEW);
    END IF;

    IF OLD.email IS DISTINCT FROM NEW.email THEN
        PERFORM public.log_customer_event('email', OLD, NEW);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.customer_update_log_on_trigger() OWNER TO postgres;


CREATE FUNCTION public.days_in_month(month_in date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  today date := CURRENT_DATE;
BEGIN
  IF DATE_TRUNC('month', month_in) = DATE_TRUNC('month', today) THEN
    -- If it's the current month, return days so far in the month
    RETURN EXTRACT(DAY FROM today);
  ELSE
   RETURN (
    SELECT DATE_PART('days', DATE_TRUNC('month', month_in) + '1 MONTH'::INTERVAL - '1 DAY'::INTERVAL)
  );
  END IF;
END;
$$;


ALTER FUNCTION public.days_in_month(month_in date) OWNER TO postgres;


CREATE FUNCTION public.days_in_month_all(month_in date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN EXTRACT(DAY FROM 
        (DATE_TRUNC('month', month_in) + '1 MONTH'::INTERVAL - '1 DAY'::INTERVAL)
    );
END;
$$;


ALTER FUNCTION public.days_in_month_all(month_in date) OWNER TO postgres;


CREATE FUNCTION public.decrypt_notification(encrypted_message text, encryption_password text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN extensions.pgp_sym_decrypt(
        encrypted_message::bytea,
        encryption_password
    );
EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'Failed to decrypt message: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.decrypt_notification(encrypted_message text, encryption_password text) OWNER TO postgres;


CREATE FUNCTION public.delete_customer(customer_email text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM public.customer_invites WHERE customer = (SELECT id FROM customers WHERE email = customer_email);
  DELETE FROM public.customers WHERE email = customer_email;
  DELETE FROM auth.users WHERE email = customer_email;
END;
$$;


ALTER FUNCTION public.delete_customer(customer_email text) OWNER TO postgres;


CREATE FUNCTION public.delete_property(property_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  accounts_to_delete uuid[];
BEGIN

  SELECT ARRAY(
    SELECT id FROM accounts 
    WHERE property = property_id
  ) INTO accounts_to_delete;
  
  PERFORM public.log_array_of_uuid(accounts_to_delete, 'accounts_to_delete');
  
  DELETE FROM account_events WHERE account = ANY(accounts_to_delete);
  DELETE FROM customer_accounts WHERE account = ANY(accounts_to_delete);

  UPDATE contracts
  SET end_date = NOW()
  WHERE id IN (
    SELECT current_contract FROM accounts
    WHERE id = ANY(accounts_to_delete)
  );

  DELETE FROM accounts WHERE id = ANY(accounts_to_delete);

  UPDATE properties SET solar_meter = null WHERE id = property_id;
  UPDATE properties SET supply_meter = null WHERE id = property_id;
  
  DELETE FROM properties WHERE id = property_id;
END;
$$;


ALTER FUNCTION public.delete_property(property_id uuid) OWNER TO postgres;


CREATE FUNCTION public.delete_property_and_customers(property_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  customers_to_delete text[];
  customer_email text;
BEGIN
  SELECT ARRAY(
    SELECT email
    from customers
    where id IN (
        select customer from customer_accounts where account in (
            select id from accounts where property = property_id
        )
    )
  ) INTO customers_to_delete;

  PERFORM public.delete_property(property_id);
  RAISE NOTICE 'Deleted property with UUID: %', property_id;

  FOREACH customer_email IN ARRAY customers_to_delete
  LOOP
    PERFORM public.delete_customer(customer_email);
    RAISE NOTICE 'Deleted customer with email: %', customer_email;
  END LOOP;
END;
$$;


ALTER FUNCTION public.delete_property_and_customers(property_id uuid) OWNER TO postgres;


CREATE FUNCTION public.diff_rows(old_row jsonb, new_row jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    diff jsonb := '{}'::jsonb; -- Initialize an empty jsonb object
    key text;
    old_value jsonb;
    new_value jsonb;
BEGIN
    FOR key IN SELECT jsonb_object_keys(new_row) LOOP
        old_value := old_row -> key; -- Get the old value for the key
        new_value := new_row -> key; -- Get the new value for the key

        IF old_value IS DISTINCT FROM new_value THEN
            diff := diff || jsonb_build_object(key, jsonb_build_object('old', old_value, 'new', new_value));
        END IF;
    END LOOP;
    RETURN diff;
END;
$$;


ALTER FUNCTION public.diff_rows(old_row jsonb, new_row jsonb) OWNER TO postgres;


CREATE FUNCTION public.email_for_auth_user_id(authuserid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
	SELECT email FROM auth.users WHERE "id" = authUserId::uuid;
$$;


ALTER FUNCTION public.email_for_auth_user_id(authuserid text) OWNER TO postgres;


CREATE FUNCTION public.generate_allocated_solar_credits(month_in date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    allocation record;
    current_property uuid;
    net_capacity real;
    esco_id uuid;
    credit_per_day numeric;
    days_in_month integer;
    base_credit numeric;
BEGIN
    -- Get number of days in the month
    SELECT public.days_in_month_all(month_in) INTO days_in_month;

    -- First, handle direct credits (properties with solar installations but no allocations)
    FOR current_property IN 
        SELECT p.id
        FROM public.properties p
        JOIN public.solar_installation si ON si.property = p.id
        WHERE NOT EXISTS (
            SELECT 1 FROM public.solar_credit_allocation sca
            WHERE sca.installation_property = p.id
        )
    LOOP
        -- Calculate credit amount before inserting
        SELECT si.declared_net_capacity, p.esco
        FROM public.properties p
        LEFT JOIN public.solar_installation si ON si.property = p.id
        WHERE p.id = current_property
        INTO net_capacity, esco_id;
        
        -- Skip if no net capacity
        IF net_capacity IS NULL OR net_capacity <= 0 THEN
            CONTINUE;
        END IF;
        
        -- Get credit rate
        SELECT credit_pence_per_day
        FROM public.solar_credit_tariffs
        WHERE esco = esco_id
        AND period_start <= month_in
        ORDER BY period_start DESC
        LIMIT 1
        INTO credit_per_day;
        
        -- Skip if no credit rate found
        IF credit_per_day IS NULL OR credit_per_day <= 0 THEN
            CONTINUE;
        END IF;
        
        -- Calculate credit amount
        base_credit := trunc(net_capacity * days_in_month * credit_per_day);
        
        -- Only insert if credit amount is greater than zero
        IF base_credit > 0 THEN
            INSERT INTO public.monthly_solar_credits 
                (property_id, month, source_installation, allocation_ratio, credit_pence)
            VALUES 
                (current_property, month_in, current_property, 1.0, base_credit)
            ON CONFLICT (property_id, month) DO UPDATE
            SET source_installation = EXCLUDED.source_installation,
                allocation_ratio = EXCLUDED.allocation_ratio,
                credit_pence = EXCLUDED.credit_pence;
        END IF;
    END LOOP;

    -- Then handle allocated credits
    FOR allocation IN 
        SELECT 
            sca.installation_property,
            sca.allocation_property,
            sca.ratio
        FROM public.solar_credit_allocation sca
    LOOP
        -- Calculate credit amount before inserting
        SELECT si.declared_net_capacity, p.esco
        FROM public.properties p
        LEFT JOIN public.solar_installation si ON si.property = p.id
        WHERE p.id = allocation.installation_property
        INTO net_capacity, esco_id;
        
        -- Skip if no net capacity
        IF net_capacity IS NULL OR net_capacity <= 0 THEN
            CONTINUE;
        END IF;
        
        -- Get credit rate
        SELECT credit_pence_per_day
        FROM public.solar_credit_tariffs
        WHERE esco = esco_id
        AND period_start <= month_in
        ORDER BY period_start DESC
        LIMIT 1
        INTO credit_per_day;
        
        -- Skip if no credit rate found
        IF credit_per_day IS NULL OR credit_per_day <= 0 THEN
            CONTINUE;
        END IF;
        
        -- Calculate credit amount with allocation ratio
        base_credit := trunc(net_capacity * days_in_month * credit_per_day * allocation.ratio);
        
        -- Only insert if credit amount is greater than zero
        IF base_credit > 0 THEN
            INSERT INTO public.monthly_solar_credits 
                (property_id, month, source_installation, allocation_ratio, credit_pence)
            VALUES (
                allocation.allocation_property,
                month_in,
                allocation.installation_property,
                allocation.ratio,
                base_credit
            )
            ON CONFLICT (property_id, month) DO UPDATE
            SET source_installation = EXCLUDED.source_installation,
                allocation_ratio = EXCLUDED.allocation_ratio,
                credit_pence = EXCLUDED.credit_pence;
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION public.generate_allocated_solar_credits(month_in date) OWNER TO postgres;


CREATE FUNCTION public.generate_new_quarter_tariffs(month_in date) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  customer_rec RECORD;
  esco_rec RECORD;
  previous_rate INTEGER;
  previous_emergency_credit NUMERIC;
  previous_debt_recovery_rate NUMERIC;
  previous_ecredit_button_threshold NUMERIC;
  default_rate CONSTANT INTEGER := 25; -- Default rate if no previous rate found
  default_emergency_credit CONSTANT NUMERIC := 15; -- Default emergency credit amount
  default_debt_recovery_rate CONSTANT NUMERIC := 0.25; -- Default debt recovery rate
  default_ecredit_button_threshold CONSTANT NUMERIC := 10; -- Default emergency credit button threshold
  prev_quarter_start date;
  microgrid_updated_count INTEGER := 0;
  customer_updated_count INTEGER := 0;
BEGIN
  -- Calculate start of previous quarter (3 months before current month)
  prev_quarter_start := (month_in - INTERVAL '3 months')::date;
  
  -- Part 1: Update microgrid_tariffs for all escos
  FOR esco_rec IN (
    SELECT DISTINCT esco
    FROM public.microgrid_tariffs
  ) LOOP
    -- Try to find the previous quarter's microgrid tariff
    SELECT 
      discount_rate_basis_points, 
      emergency_credit, 
      debt_recovery_rate, 
      ecredit_button_threshold 
    INTO 
      previous_rate, 
      previous_emergency_credit, 
      previous_debt_recovery_rate, 
      previous_ecredit_button_threshold
    FROM public.microgrid_tariffs
    WHERE 
      esco = esco_rec.esco
      AND period_start >= prev_quarter_start
      AND period_start < month_in
    ORDER BY period_start DESC
    LIMIT 1;
    
    -- If no previous tariff found, use default values
    IF previous_rate IS NULL THEN
      previous_rate := default_rate;
      previous_emergency_credit := default_emergency_credit;
      previous_debt_recovery_rate := default_debt_recovery_rate;
      previous_ecredit_button_threshold := default_ecredit_button_threshold;
    END IF;
    
    -- Insert new microgrid tariff record
    INSERT INTO public.microgrid_tariffs(
      esco, 
      period_start, 
      discount_rate_basis_points, 
      emergency_credit, 
      debt_recovery_rate, 
      ecredit_button_threshold
    )
    VALUES (
      esco_rec.esco, 
      month_in, 
      previous_rate, 
      previous_emergency_credit, 
      previous_debt_recovery_rate, 
      previous_ecredit_button_threshold
    )
    ON CONFLICT (esco, period_start) 
    DO UPDATE SET 
      discount_rate_basis_points = EXCLUDED.discount_rate_basis_points,
      emergency_credit = EXCLUDED.emergency_credit,
      debt_recovery_rate = EXCLUDED.debt_recovery_rate,
      ecredit_button_threshold = EXCLUDED.ecredit_button_threshold;
    
    microgrid_updated_count := microgrid_updated_count + 1;
  END LOOP;
  
  
  -- Part 2: Update customer_tariffs for eligible customers
  
  FOR customer_rec IN (
    SELECT c.id, c.email
    FROM public.customers c
    JOIN public.customer_accounts ca ON ca.customer = c.id
    JOIN public.accounts a ON a.id = ca.account
    WHERE c.status IN ('live', 'prelive', 'onboarding')
    AND ca.role = 'occupier'
    AND a.type = 'supply'
  ) LOOP
    -- Try to find the previous quarter's rate for this customer
    SELECT discount_rate_basis_points INTO previous_rate
    FROM public.customer_tariffs ct
    WHERE 
      ct.customer = customer_rec.id
      AND ct.period_start >= prev_quarter_start
      AND ct.period_start < month_in
    ORDER BY ct.period_start DESC
    LIMIT 1;
    
    -- If no previous rate found, use the default rate
    IF previous_rate IS NULL THEN
      previous_rate := default_rate;
    END IF;
    
    -- Insert new tariff record
    -- The computed_unit_rate and computed_standing_charge are auto-calculated by triggers
    INSERT INTO public.customer_tariffs(customer, period_start, discount_rate_basis_points)
    VALUES (customer_rec.id, month_in, previous_rate)
    ON CONFLICT (customer, period_start) 
    DO UPDATE SET discount_rate_basis_points = EXCLUDED.discount_rate_basis_points;
    
  RAISE NOTICE 'Updated tariffs for % ESCOs and % customers starting from %', 
    microgrid_updated_count, customer_updated_count, month_in;
  END LOOP;
END;
$$;


ALTER FUNCTION public.generate_new_quarter_tariffs(month_in date) OWNER TO postgres;


COMMENT ON FUNCTION public.generate_new_quarter_tariffs(month_in date) IS 'Generates both microgrid and customer tariffs for a new quarter.
Takes a date parameter representing the start of the new quarter.

For microgrid tariffs:
- Updates all ESCOs currently in the microgrid_tariffs table
- Carries over discount rates and emergency credit settings from the previous quarter
- Uses default values if no previous quarter data exists

For customer tariffs:
- Creates tariff records for customers with status "live" or "prelive", plus specified test accounts
- Carries over discount rates from the previous quarter, or uses default rate of 25 if no previous rate found
- Auto-computed columns are calculated by database triggers';



CREATE FUNCTION public.generate_random_meter_serial() RETURNS text
    LANGUAGE plpgsql
    AS $$
    declare
        serial text := (SELECT 'UNKNOWN_' || (random() * 1000000)::int);
BEGIN
    RETURN serial;
END;
$$;


ALTER FUNCTION public.generate_random_meter_serial() OWNER TO postgres;


CREATE FUNCTION public.generate_v4_uuid_from_hash(input_text text) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    hash_hex text;
    uuid_hex text;
BEGIN
    hash_hex := md5(input_text);
    
    -- Set version to 4 (random) by replacing the 13th hex digit with '4'
    -- Set variant to 10xx by replacing the 17th hex digit with '8', '9', 'a', or 'b'
    uuid_hex := substring(hash_hex, 1, 8) || '-' || 
                substring(hash_hex, 9, 4) || '-' || 
                '4' || substring(hash_hex, 14, 3) || '-' || 
                '8' || substring(hash_hex, 18, 3) || '-' || 
                substring(hash_hex, 21, 12);
                
    RETURN uuid_hex::uuid;
END;
$$;


ALTER FUNCTION public.generate_v4_uuid_from_hash(input_text text) OWNER TO postgres;


CREATE TABLE public.contract_terms (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type public.contract_type_enum NOT NULL,
    docuseal_template_id integer,
    docuseal_template_slug text,
    summary_text text NOT NULL,
    subtype public.contract_subtype_enum,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    short_description text,
    preview_only boolean DEFAULT false NOT NULL
);


ALTER TABLE public.contract_terms OWNER TO postgres;


COMMENT ON TABLE public.contract_terms IS 'Stores the terms of a given contract version and the id of the associated document template in docuseal.

see the contracts table for per account instances of these terms.';



COMMENT ON COLUMN public.contract_terms.docuseal_template_id IS 'Id of a corresponding template in the docuseal system. eg. 5432';



COMMENT ON COLUMN public.contract_terms.docuseal_template_slug IS 'Slug of a corresponding template in the docuseal system.

For example "7NR5FJT6NdSEvb" is a slug and will be used in the URI https://docuseal.co/d/7NR5FJT6NdSEvb to request a signature from a customer.';



COMMENT ON COLUMN public.contract_terms.summary_text IS 'A paragraph length description of the contract for display in the UI at contract selection time.';



COMMENT ON COLUMN public.contract_terms.short_description IS 'A short one line description of the terms for display in the UI.';



COMMENT ON COLUMN public.contract_terms.preview_only IS 'If true show contract in preview / read only mode in docuseal.';



CREATE FUNCTION public.get_contract_terms_for_esco(esco_param text) RETURNS SETOF public.contract_terms
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    is_uuid boolean;
    esco_id uuid;
BEGIN
    -- Check if the input parameter is a valid UUID
    BEGIN
        esco_id := esco_param::uuid;
        is_uuid := true;
    EXCEPTION WHEN others THEN
        is_uuid := false;
    END;

    -- Query based on whether the input is a UUID or a code
    IF is_uuid THEN
        RETURN QUERY
        SELECT ct.*
        FROM 
            public.contract_terms ct
        JOIN 
            public.contract_terms_esco cte ON ct.id = cte.terms
        WHERE 
            cte.esco = esco_id
        ORDER BY 
            ct.type, ct.version DESC;
    ELSE
        RETURN QUERY
        SELECT ct.*
        FROM 
            public.contract_terms ct
        JOIN 
            public.contract_terms_esco cte ON ct.id = cte.terms
        JOIN 
            public.escos e ON cte.esco = e.id
        WHERE 
            e.code = esco_param
        ORDER BY 
            ct.type, ct.version DESC;
    END IF;
END;
$$;


ALTER FUNCTION public.get_contract_terms_for_esco(esco_param text) OWNER TO postgres;


COMMENT ON FUNCTION public.get_contract_terms_for_esco(esco_param text) IS 'Gets all contract terms for a given ESCO, identified either by UUID or code.
Returns the full contract_terms rows ordered by type and version (descending).';



CREATE FUNCTION public.get_property_owners_for_auth_user(email_in text) RETURNS SETOF uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT p.owner
    FROM public.properties p
    JOIN public.accounts a ON a.property = p.id
    JOIN public.customer_accounts ca ON ca.account = a.id
    JOIN public.customers c ON ca.customer = c.id
    WHERE c.email = email_in;
END;
$$;


ALTER FUNCTION public.get_property_owners_for_auth_user(email_in text) OWNER TO postgres;


CREATE FUNCTION public.log_array_of_uuid(uuids uuid[], label text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF array_length(uuids, 1) > 0 THEN 
    FOR i IN 1..array_length(uuids, 1) LOOP
      RAISE NOTICE '%: %', label, uuids[i];
    END LOOP;
  ELSE
    RAISE NOTICE '% array is empty!', label; 
  END IF;
END;
$$;


ALTER FUNCTION public.log_array_of_uuid(uuids uuid[], label text) OWNER TO postgres;


CREATE FUNCTION public.log_customer_event(event_type text, old_row public.customers, new_row public.customers) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
    INSERT INTO public.customer_events(customer, event_type, data) 
        VALUES (
            new_row.id,
            event_type, 
            jsonb_build_object('changed', public.diff_rows(to_jsonb(old_row), to_jsonb(new_row)), 'old_row', old_row, 'new_row', new_row)
        );
$$;


ALTER FUNCTION public.log_customer_event(event_type text, old_row public.customers, new_row public.customers) OWNER TO postgres;


CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account uuid NOT NULL,
    amount_pence integer NOT NULL,
    status public.payment_status_enum DEFAULT 'created'::public.payment_status_enum NOT NULL,
    payment_intent text,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    receipt_url text,
    scheduled_at timestamp with time zone,
    submitted_at timestamp with time zone,
    CONSTRAINT payments_amount_check CHECK (((amount_pence > 0) AND (amount_pence <= 100000)))
);


ALTER TABLE public.payments OWNER TO postgres;


COMMENT ON COLUMN public.payments.scheduled_at IS 'Approximate time to submit this payment to Stripe. Exact time submitted will be captured in submitted_at.';



COMMENT ON COLUMN public.payments.submitted_at IS 'Time the payment was submitted to stripe. This is the payment intent created timestamp.';


CREATE TABLE public.microgrid_tariffs (
    esco uuid NOT NULL,
    period_start date NOT NULL,
    discount_rate_basis_points integer NOT NULL,
    computed_unit_rate numeric,
    computed_standing_charge numeric,
    emergency_credit numeric,
    debt_recovery_rate numeric,
    ecredit_button_threshold numeric,
    CONSTRAINT microgrid_tariffs_discount_rate_check CHECK (((discount_rate_basis_points >= 0) AND (discount_rate_basis_points <= 100))),
    CONSTRAINT microgrid_tariffs_emergency_credit_check CHECK (((debt_recovery_rate >= (0)::numeric) AND (debt_recovery_rate <= (500)::numeric) AND ((emergency_credit >= (0)::numeric) AND (emergency_credit <= (5000)::numeric)) AND ((ecredit_button_threshold >= (0)::numeric) AND (ecredit_button_threshold <= (5000)::numeric))))
);


ALTER TABLE public.microgrid_tariffs OWNER TO postgres;


COMMENT ON TABLE public.microgrid_tariffs IS 'Microgrid tariffs stores tariff discounts against the benchmark.

These are used for information purposes, not for calculating actual customer tariffs as these are computed against the benchmark.

It is also where we put the emergency credit settings which are at this stage per microgrid.';



CREATE TABLE public.monthly_costs (
    customer_id uuid NOT NULL,
    month date NOT NULL,
    power numeric,
    heat numeric,
    standing_charge numeric,
    total numeric,
    microgrid_power numeric,
    microgrid_heat numeric,
    microgrid_standing_charge numeric,
    microgrid_total numeric,
    benchmark_power numeric,
    benchmark_heat numeric,
    benchmark_standing_charge numeric,
    benchmark_total numeric,
    updated_at date DEFAULT now() NOT NULL,
    created_at date DEFAULT now() NOT NULL
);


ALTER TABLE public.monthly_costs OWNER TO postgres;


CREATE TABLE public.monthly_usage (
    circuit_id uuid NOT NULL,
    month date NOT NULL,
    kwh numeric NOT NULL
);


ALTER TABLE public.monthly_usage OWNER TO postgres;


CREATE TABLE public.payment_events (
    payment uuid NOT NULL,
    event_type text NOT NULL,
    data jsonb,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);


ALTER TABLE public.payment_events OWNER TO postgres;


CREATE TABLE public.places (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    parent uuid,
    place text NOT NULL
);


ALTER TABLE public.places OWNER TO postgres;


CREATE TABLE public.postgres_notifications (
    channel text NOT NULL,
    event text,
    payload jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);


ALTER TABLE public.postgres_notifications OWNER TO postgres;


CREATE TABLE public.regions (
    code text NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.regions OWNER TO postgres;


COMMENT ON TABLE public.regions IS 'Regions of UK as used in the Ofgem energy price caps: https://www.ofgem.gov.uk/energy-advice-households/get-energy-price-cap-standing-charges-and-unit-rates-region';



CREATE TABLE public.solar_credit_allocation (
    installation_property uuid NOT NULL,
    allocation_property uuid NOT NULL,
    ratio numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT solar_credit_allocation_ratio_check CHECK (((ratio >= (0)::numeric) AND (ratio <= (1)::numeric)))
);


ALTER TABLE public.solar_credit_allocation OWNER TO postgres;


CREATE TABLE public.solar_credit_tariffs (
    esco uuid NOT NULL,
    period_start date NOT NULL,
    credit_pence_per_year numeric NOT NULL,
    credit_pence_per_day numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT solar_credit_tariffs_credit_range_check CHECK (((credit_pence_per_year >= (0)::numeric) AND (credit_pence_per_year <= (30000)::numeric)))
);


ALTER TABLE public.solar_credit_tariffs OWNER TO postgres;


COMMENT ON TABLE public.solar_credit_tariffs IS 'Stores the solar credit tariffs that determine how much credit customers receive for their solar generation';



COMMENT ON COLUMN public.solar_credit_tariffs.credit_pence_per_year IS 'Annual credit amount in pence';



COMMENT ON COLUMN public.solar_credit_tariffs.credit_pence_per_day IS 'Daily credit amount in pence, computed automatically from the yearly amount';



CREATE TABLE public.solar_installation (
    property uuid NOT NULL,
    mcs text NOT NULL,
    declared_net_capacity real,
    commissioning_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.solar_installation OWNER TO postgres;


CREATE TABLE public.topup_events (
    topup uuid NOT NULL,
    event_type public.topup_event_enum NOT NULL,
    data jsonb,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);


ALTER TABLE public.topup_events OWNER TO postgres;


CREATE TABLE public.topups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    meter uuid NOT NULL,
    amount_pence integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    status public.topup_status_enum NOT NULL,
    source public.topup_source_enum,
    notes text,
    token text,
    reference text,
    acquired_at timestamp with time zone,
    used_at timestamp with time zone,
    CONSTRAINT topups_amount_check CHECK (((amount_pence >= '-50000'::integer) AND (amount_pence <= 100000)))
);


ALTER TABLE public.topups OWNER TO postgres;


COMMENT ON COLUMN public.topups.notes IS 'Notes about the topup. eg. reason for gift.';



CREATE TABLE public.topups_monthly_solar_credits (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    topup_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    month_solar_credit_id uuid NOT NULL
);


ALTER TABLE public.topups_monthly_solar_credits OWNER TO postgres;


COMMENT ON TABLE public.topups_monthly_solar_credits IS 'Links monthly solar credits to topups that were created from them';



CREATE TABLE public.topups_payments (
    payment_id uuid NOT NULL,
    topup_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.topups_payments OWNER TO postgres;


COMMENT ON TABLE public.topups_payments IS 'Links payments to topups that were created from them';



CREATE TABLE public.transaction_statuses (
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    transaction uuid NOT NULL,
    status text NOT NULL,
    available_balance numeric NOT NULL
);


ALTER TABLE public.transaction_statuses OWNER TO postgres;


CREATE TABLE public.transactions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    type text NOT NULL,
    name text,
    reference text,
    amount numeric NOT NULL,
    balance numeric NOT NULL,
    account uuid NOT NULL
);


ALTER TABLE public.transactions OWNER TO postgres;


CREATE TABLE public.wallets (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    balance numeric DEFAULT 0,
    last_sync_timestamp timestamp with time zone,
    topup_amount integer DEFAULT 50 NOT NULL,
    topup_threshold integer DEFAULT 20 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.wallets OWNER TO postgres;



CREATE FUNCTION public.log_payment_event(event_type text, old_row public.payments, new_row public.payments) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
    INSERT INTO public.payment_events(payment, event_type, data) 
        VALUES (
            new_row.id,
            event_type, 
            jsonb_build_object('changed', public.diff_rows(to_jsonb(old_row), to_jsonb(new_row)), 'old_row', old_row, 'new_row', new_row)
        );
$$;


ALTER FUNCTION public.log_payment_event(event_type text, old_row public.payments, new_row public.payments) OWNER TO postgres;


CREATE FUNCTION public.log_postgres_notification(channel text, notify_or_listen text, payload text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  INSERT INTO public.postgres_notifications(channel, event, payload)
    VALUES(channel, notify_or_listen, payload::jsonb);
END;
$$;


ALTER FUNCTION public.log_postgres_notification(channel text, notify_or_listen text, payload text) OWNER TO postgres;


CREATE FUNCTION public.meter_prepay_status_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    customer_ids uuid[];
BEGIN
    -- Find customers who are occupiers of supply accounts using this meter
    SELECT array_agg(DISTINCT ca.customer)
    FROM public.customer_accounts ca
    JOIN public.accounts a ON a.id = ca.account
    JOIN public.properties p ON p.id = a.property
    WHERE p.supply_meter = NEW.id
    AND ca.role = 'occupier'
    AND a.type = 'supply'
    INTO customer_ids;
    
    -- Update status for these customers
    IF customer_ids IS NOT NULL AND array_length(customer_ids, 1) > 0 THEN
        FOR i IN 1..array_length(customer_ids, 1) LOOP
            UPDATE public.customers
            SET status = public.customer_status(customers)
            WHERE id = customer_ids[i];
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.meter_prepay_status_change() OWNER TO postgres;


CREATE FUNCTION public.meters_missing_future_tariffs(esco_code_in text) RETURNS TABLE(serial text, meter_id uuid, customer_id uuid, customer_email text, esco_code text, tariff_period_start date, customer_unit_rate numeric, customer_standing_charge numeric, emergency_credit numeric, debt_recovery_rate numeric, ecredit_button_threshold numeric, current_future_standing_charge numeric, current_future_unit_rate_a numeric, current_future_unit_rate_b numeric, current_future_activation_datetime timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
    now_date DATE := CURRENT_DATE;
BEGIN
    RETURN QUERY
    WITH future_tariffs AS (
        -- Get customer tariffs with future dates (after current month)
        SELECT 
            ct.customer,
            ct.period_start,
            ct.computed_unit_rate,
            ct.computed_standing_charge,
            c.email AS customer_email
        FROM 
            public.customer_tariffs ct
        JOIN 
            public.customers c ON ct.customer = c.id
        WHERE 
            ct.period_start > now_date
        ORDER BY 
            ct.period_start ASC
    ),
    customer_meters AS (
        -- Connect customers to their supply meters via the account chain
        SELECT 
            ft.customer,
            ft.customer_email,
            ft.period_start,
            ft.computed_unit_rate,
            ft.computed_standing_charge,
            m.id AS meter_id,
            m.serial,
            e.code AS esco_code,
            e.id AS esco_id
        FROM 
            future_tariffs ft
        JOIN 
            public.customer_accounts ca ON ft.customer = ca.customer
        JOIN 
            public.accounts a ON ca.account = a.id
        JOIN 
            public.properties p ON a.property = p.id
        JOIN 
            public.meters m ON p.supply_meter = m.id
        JOIN 
            public.escos e ON p.esco = e.id
        WHERE 
            a.type = 'supply'
            AND ca.role = 'occupier'
            AND (esco_code_in IS NULL OR e.code = esco_code_in)
    ),
    esco_emergency_settings AS (
        -- Get emergency credit settings from microgrid_tariffs
        SELECT 
            mt.esco,
            mt.emergency_credit,
            mt.debt_recovery_rate,
            mt.ecredit_button_threshold
        FROM 
            public.microgrid_tariffs mt
        JOIN (
            SELECT 
                esco,
                MAX(period_start) AS latest_start
            FROM 
                public.microgrid_tariffs
            WHERE 
                period_start > now_date
            GROUP BY 
                esco
        ) latest ON mt.esco = latest.esco AND mt.period_start = latest.latest_start
    )
    -- Final query joining with meter_shadows_tariffs
    SELECT 
        cm.serial,
        cm.meter_id,
        cm.customer,
        cm.customer_email,
        cm.esco_code,
        cm.period_start,
        cm.computed_unit_rate,
        cm.computed_standing_charge,
        ees.emergency_credit,
        ees.debt_recovery_rate,
        ees.ecredit_button_threshold,
        mst.future_standing_charge,
        mst.future_unit_rate_a,
        mst.future_unit_rate_b,
        mst.future_activation_datetime
    FROM 
        customer_meters cm
    LEFT JOIN 
        flows.meter_shadows_tariffs mst ON cm.serial = mst.serial
    LEFT JOIN 
        esco_emergency_settings ees ON cm.esco_id = ees.esco
    WHERE 
        -- Meters with no future tariff set
        mst.future_activation_datetime IS NULL
        OR 
        -- Meters with future tariff set but for a different date than the expected period_start
        (DATE(mst.future_activation_datetime) <> cm.period_start)
        OR
        -- Meters with mismatched tariff values
        (ABS(COALESCE(mst.future_standing_charge, 0) - cm.computed_standing_charge) > 0.0001
         OR ABS(COALESCE(mst.future_unit_rate_a, 0) - cm.computed_unit_rate) > 0.0001
         OR ABS(COALESCE(mst.future_unit_rate_b, 0) - cm.computed_unit_rate) > 0.0001);
END;
$$;


ALTER FUNCTION public.meters_missing_future_tariffs(esco_code_in text) OWNER TO postgres;


COMMENT ON FUNCTION public.meters_missing_future_tariffs(esco_code_in text) IS 'Identifies meters that should have future tariffs set but either don''t have them or 
have incorrect future tariff values. Returns meter details, customer info, and both
the expected tariffs and current future tariffs set on the meters.

Parameters:
  esco_code_in - ESCO code to filter by (e.g., "wlce"). If NULL, returns data for all ESCOs.

The function checks for:
1. Meters with no future tariff set (future_activation_datetime IS NULL)
2. Meters with future tariff set but for incorrect date
3. Meters with mismatched future tariff values

The function also includes emergency credit settings from microgrid_tariffs.';



CREATE FUNCTION public.meters_with_incorrect_threshold_settings() RETURNS text[]
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
	RETURN (
	    SELECT array_agg(r.serial)
	    FROM flows.meter_shadows s, flows.meter_registry r
	    WHERE s.id = r.id
	    AND NOT (
	        s.tariffs_active @> '{"threshold_mask": [{"rate1": false, "rate2": false, "rate3": false, "rate4": false, "rate5": false, "rate6": false, "rate7": false, "rate8": false}]}'
	    AND
	        s.tariffs_active @> '{"threshold_values": [{"th1": 0, "th2": 0, "th3": 0, "th4": 0, "th5": 0, "th6": 0, "th7": 0}]}'
	    )
	);
END;
$$;


ALTER FUNCTION public.meters_with_incorrect_threshold_settings() OWNER TO postgres;


CREATE FUNCTION public.meters_with_unsynced_emergency_credit_settings(esco_filter text) RETURNS TABLE(serial text, active_ecredit_availability text, active_debt_recovery_rate text, active_emergency_credit text, expected_ecredit_availability text, expected_debt_recovery_rate text, expected_emergency_credit text)
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
	RETURN QUERY
	with ecredit_props as (
		select esco, period_start, emergency_credit, ecredit_button_threshold, debt_recovery_rate 
		from public.microgrid_tariffs mt 
		where 
			(esco = (select id from public.escos e where code = esco_filter)) and
			period_start < now()
		order by period_start desc
		limit 1 
	) select 
		r.serial,
		s.tariffs_active->>'prepayment_ecredit_availability' as "active_ecredit_availability",
		s.tariffs_active->>'prepayment_debt_recovery_rate' as "active_debt_recovery_rate",
		s.tariffs_active->>'prepayment_emergency_credit' as "active_emergency_credit",
		e.ecredit_button_threshold::text as "expected_ecredit_availability",
		e.debt_recovery_rate::text as "expected_debt_recovery_rate",
		e.emergency_credit::text as "expected_emergency_credit"
	  from flows.meter_registry r, flows.meter_shadows s, ecredit_props e
	  where r.id = s.id
	  and r.esco = e.esco
	  and (
	  	(s.tariffs_active->>'prepayment_ecredit_availability')::numeric != e.ecredit_button_threshold or 
	  	(s.tariffs_active->>'prepayment_debt_recovery_rate')::numeric != e.debt_recovery_rate or 
	  	(s.tariffs_active->>'prepayment_emergency_credit')::numeric != e.emergency_credit 
	  );
END;
$$;


ALTER FUNCTION public.meters_with_unsynced_emergency_credit_settings(esco_filter text) OWNER TO postgres;


CREATE FUNCTION public.microgrid_month_standing_charge(esco_code_in text, month_in date) RETURNS numeric
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
    microgrid_standing_charge numeric;
  num_days int4;
BEGIN
  SELECT mt.computed_standing_charge
  FROM public.microgrid_tariffs mt, public.escos e
  WHERE mt.period_start <= month_in
    AND mt.esco = e.id
    AND e.code = esco_code_in
  ORDER BY mt.period_start desc
  LIMIT 1
    INTO microgrid_standing_charge;

  SELECT public.days_in_month(month_in)
    INTO num_days;
  
  RETURN microgrid_standing_charge * num_days;
END;
$$;


ALTER FUNCTION public.microgrid_month_standing_charge(esco_code_in text, month_in date) OWNER TO postgres;


CREATE FUNCTION public.microgrid_tariffs_compute_rates() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    benchmark_standing_charge numeric;
    benchmark_unit_rate numeric;
BEGIN
	SELECT standing_charge, unit_rate
	FROM public.benchmark_tariffs
	WHERE period_start <= NEW.period_start
	ORDER BY period_start desc
	LIMIT 1
		INTO benchmark_standing_charge, benchmark_unit_rate;
    
	NEW.computed_standing_charge = (1 - (NEW.discount_rate_basis_points::numeric / 100)) * benchmark_standing_charge;
	NEW.computed_unit_rate = (1 - (NEW.discount_rate_basis_points::numeric / 100)) * benchmark_unit_rate;
	
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.microgrid_tariffs_compute_rates() OWNER TO postgres;


CREATE FUNCTION public.microgrid_unit_rate(esco_code_in text, month_in date) RETURNS numeric
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  unit_rate numeric;
BEGIN
  SELECT mt.computed_unit_rate
  FROM public.microgrid_tariffs mt, public.escos e
  WHERE mt.period_start <= month_in
    AND mt.esco = e.id
    AND e.code = esco_code_in
  ORDER BY mt.period_start desc
  LIMIT 1
    INTO unit_rate;
  
  RETURN unit_rate;
END;
$$;


ALTER FUNCTION public.microgrid_unit_rate(esco_code_in text, month_in date) OWNER TO postgres;


CREATE FUNCTION public.monthly_costs_compute(month_in date) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  result_rows public.monthly_costs_compute_query_result_row_type[];
  row_data public.monthly_costs_compute_query_result_row_type;
  customers_processed_map JSONB := '{}'::JSONB;
  days_in_month int;
  benchmark_unit_rate numeric;
  benchmark_sc numeric;
  benchmark_usage numeric;
  microgrid_unit_rate numeric;
  microgrid_sc numeric;
  microgrid_usage numeric;
  customer_unit_rate numeric;
  customer_sc numeric;
  standing_charge_cost numeric;
  usage_cost numeric;
BEGIN
  SELECT ARRAY(
    SELECT ROW(
      mu.circuit_id, mu.kwh, ca.customer, c.type, e.code, e.region
    )::public.monthly_costs_compute_query_result_row_type
    FROM
      public.monthly_usage mu,
      public.customer_accounts ca,
      public.circuit_meter cm,
      public.properties p,
      public.accounts a,
      public.circuits c,
      public.escos e
    WHERE mu.month = month_in
    and cm.circuit_id = mu.circuit_id
    and cm.circuit_id = c.id
    and cm.meter_id = p.supply_meter
    and a.property = p.id
    and p.esco = e.id
    and a.id = ca.account
    and ca."role" = 'occupier'
  ) INTO result_rows;

  FOREACH row_data IN ARRAY result_rows
  LOOP
    RAISE NOTICE 'processing usage for customer: % circuit: % kwh: %', row_data.customer, row_data.circuit_id, row_data.kwh;

    SELECT computed_standing_charge, computed_unit_rate
    FROM public.customer_tariffs
    WHERE customer = row_data.customer
    AND period_start <= month_in
    ORDER BY period_start desc
    LIMIT 1
      INTO customer_sc, customer_unit_rate;

    IF customer_sc is null or customer_unit_rate is null THEN
        RAISE NOTICE 'skipping customer % ... no tariff in table', row_data.customer;
        CONTINUE;
    END IF;

    RAISE NOTICE 'customer % tariffs: standing: % unit (%): %',
          row_data.customer, customer_sc, row_data.type, customer_unit_rate;
    
    usage_cost = customer_unit_rate * row_data.kwh;

    RAISE NOTICE '% circuit usage: %', row_data.customer, usage_cost;

    SELECT public.benchmark_unit_rate(row_data.region, month_in)
      INTO benchmark_unit_rate;

    benchmark_usage = benchmark_unit_rate * row_data.kwh;

    SELECT public.microgrid_unit_rate(row_data.esco_code, month_in)
      INTO microgrid_unit_rate;

    microgrid_usage = microgrid_unit_rate * row_data.kwh;

    IF row_data.type = 'power' THEN
        INSERT INTO public.monthly_costs(customer_id, month, power, benchmark_power, microgrid_power) 
            VALUES(row_data.customer, month_in, usage_cost, benchmark_usage, microgrid_usage)
            ON CONFLICT (customer_id, month) DO UPDATE
            SET power = EXCLUDED.power, 
                benchmark_power = EXCLUDED.benchmark_power,
                microgrid_power = EXCLUDED.microgrid_power;
    ELSIF row_data.type = 'heat' THEN
        INSERT INTO public.monthly_costs(customer_id, month, heat, benchmark_heat, microgrid_heat) 
            VALUES(row_data.customer, month_in, usage_cost, benchmark_usage, microgrid_usage)
            ON CONFLICT (customer_id, month) DO UPDATE
            SET heat = EXCLUDED.heat, 
                benchmark_heat = EXCLUDED.benchmark_heat,
                microgrid_heat = EXCLUDED.microgrid_heat;
    END IF;

    IF NOT COALESCE((customers_processed_map ->> row_data.customer::text)::BOOLEAN, FALSE) THEN
      RAISE NOTICE 'processing standing charges for customer %', row_data.customer;
    
      SELECT public.days_in_month(month_in) INTO days_in_month;
      standing_charge_cost = customer_sc * days_in_month;

      INSERT INTO public.monthly_costs(customer_id, month, standing_charge) 
        VALUES(row_data.customer, month_in, standing_charge_cost)
        ON CONFLICT (customer_id, month) DO UPDATE
        SET standing_charge = EXCLUDED.standing_charge;

      SELECT public.benchmark_month_standing_charge(row_data.region, month_in)
        INTO benchmark_sc;
      RAISE NOTICE 'benchmark_standing_charge % region %', benchmark_sc, row_data.region;

      UPDATE public.monthly_costs set benchmark_standing_charge = benchmark_sc
        where customer_id = row_data.customer
        and month = month_in;
             
      SELECT public.microgrid_month_standing_charge(row_data.esco_code, month_in)
        into microgrid_sc;
      RAISE NOTICE 'microgrid_standing_charge % esco %', microgrid_sc, row_data.esco_code;

      UPDATE public.monthly_costs set microgrid_standing_charge = microgrid_sc
        where customer_id = row_data.customer
        and month = month_in; 
   
      customers_processed_map := customers_processed_map || jsonb_build_object(row_data.customer::text, TRUE);
    END IF;

  END LOOP;
END;
$$;


ALTER FUNCTION public.monthly_costs_compute(month_in date) OWNER TO postgres;


CREATE FUNCTION public.monthly_costs_compute_totals() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  NEW.total = 
        COALESCE(NEW.heat, 0) +
        COALESCE(NEW.power, 0) +
        COALESCE(NEW.standing_charge, 0);
  NEW.microgrid_total =
        COALESCE(NEW.microgrid_heat, 0) +
        COALESCE(NEW.microgrid_power, 0) +
        COALESCE(NEW.microgrid_standing_charge, 0);
  NEW.benchmark_total =
        COALESCE(NEW.benchmark_heat, 0) +
        COALESCE(NEW.benchmark_power, 0) +
        COALESCE(NEW.benchmark_standing_charge, 0);
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.monthly_costs_compute_totals() OWNER TO postgres;


CREATE FUNCTION public.monthly_solar_credits_compute_credit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    days_in_month integer;
    net_capacity real;
    credit_per_day numeric;
    esco_id uuid;
    base_credit numeric;
    has_allocation boolean;
BEGIN
    -- Get the number of days in the month
    SELECT public.days_in_month_all(NEW.month) INTO days_in_month;

    -- Default source installation and ratio if not provided
    IF NEW.source_installation IS NULL THEN
        NEW.source_installation := NEW.property_id;
        NEW.allocation_ratio := 1.0;
    END IF;

    -- Get the declared net capacity and esco for the source installation property
    SELECT si.declared_net_capacity, p.esco
    FROM public.properties p
    LEFT JOIN public.solar_installation si ON si.property = p.id
    WHERE p.id = NEW.source_installation
    INTO net_capacity, esco_id;

    -- If there's no solar installation, set credit to 0
    IF net_capacity IS NULL THEN
        NEW.credit_pence := 0;
        RETURN NEW;
    END IF;

    -- Get the latest applicable credit rate
    SELECT credit_pence_per_day
    FROM public.solar_credit_tariffs
    WHERE esco = esco_id
    AND period_start <= NEW.month
    ORDER BY period_start DESC
    LIMIT 1
    INTO credit_per_day;

    -- If no credit rate found, set credit to 0
    IF credit_per_day IS NULL THEN
        NEW.credit_pence := 0;
        RETURN NEW;
    END IF;

    -- Compute the base credit for the whole installation
    -- Using trunc to convert to integer, dropping decimal places
    base_credit := trunc(net_capacity * days_in_month * credit_per_day);
    
    -- Apply the allocation ratio and truncate to integer
    NEW.credit_pence := trunc(base_credit * NEW.allocation_ratio)::integer;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.monthly_solar_credits_compute_credit() OWNER TO postgres;


CREATE TABLE public.monthly_solar_credits (
    property_id uuid NOT NULL,
    month date NOT NULL,
    credit_pence integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    source_installation uuid,
    allocation_ratio numeric,
    applied_at timestamp with time zone,
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    scheduled_at timestamp with time zone DEFAULT (date_trunc('month'::text, (now() + '1 mon'::interval)) + '00:10:00'::interval)
);


ALTER TABLE public.monthly_solar_credits OWNER TO postgres;


COMMENT ON TABLE public.monthly_solar_credits IS 'Stores the monthly solar credits computed for properties with solar installations';



COMMENT ON COLUMN public.monthly_solar_credits.credit_pence IS 'Monthly credit amount in pence, computed from declared capacity and daily credit rate';



COMMENT ON COLUMN public.monthly_solar_credits.applied_at IS 'When the solar credit was added to the supply meter.';



CREATE FUNCTION public.monthly_solar_credits_unapplied(month_in text) RETURNS SETOF public.monthly_solar_credits
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT msc.* 
    FROM public.monthly_solar_credits msc, public.properties p, public.meters m
    WHERE msc.applied_at IS NULL
    AND msc.credit_pence > 0
    AND msc."month" = month_in::date
    AND msc."scheduled_at" < now()
    AND msc.property_id = p.id
    AND p.supply_meter = m.id
    AND m.prepay_enabled IS NOT FALSE;
END;
$$;


ALTER FUNCTION public.monthly_solar_credits_unapplied(month_in text) OWNER TO postgres;


CREATE FUNCTION public.notify_encrypted(channel text, message text, encryption_password text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify(
        channel,
        extensions.pgp_sym_encrypt(
            message,
            encryption_password,
            'compress-algo=2, cipher-algo=aes256'  -- Use AES-256 + ZLIB compression
        )::text
    );
END;
$$;


ALTER FUNCTION public.notify_encrypted(channel text, message text, encryption_password text) OWNER TO postgres;


CREATE FUNCTION public.payment_insert_log_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    PERFORM public.log_payment_event('payments_insert', OLD, NEW);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.payment_insert_log_on_trigger() OWNER TO postgres;


CREATE FUNCTION public.payment_update_log_on_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    PERFORM public.log_payment_event('payments_update', OLD, NEW);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.payment_update_log_on_trigger() OWNER TO postgres;


CREATE FUNCTION public.solar_credit_tariff_by_esco(esco_id uuid) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    result NUMERIC;
BEGIN
    SELECT 
        sct.credit_pence_per_year INTO result
    FROM 
        solar_credit_tariffs sct
    WHERE 
        sct.period_start = (
            SELECT MAX(period_start) 
            FROM solar_credit_tariffs 
            WHERE esco = esco_id
        )
        AND sct.esco = esco_id;
    
    RETURN result;
END;
$$;


ALTER FUNCTION public.solar_credit_tariff_by_esco(esco_id uuid) OWNER TO postgres;


CREATE FUNCTION public.solar_credit_tariffs_compute_daily_credit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if the year of period_start is a leap year
    IF (DATE_PART('year', NEW.period_start)::integer % 4 = 0 
        AND (DATE_PART('year', NEW.period_start)::integer % 100 != 0 
             OR DATE_PART('year', NEW.period_start)::integer % 400 = 0)) THEN
        -- Leap year: divide by 366
        NEW.credit_pence_per_day = NEW.credit_pence_per_year / 366;
    ELSE
        -- Non-leap year: divide by 365
        NEW.credit_pence_per_day = NEW.credit_pence_per_year / 365;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.solar_credit_tariffs_compute_daily_credit() OWNER TO postgres;


CREATE FUNCTION public.submittable_payments() RETURNS SETOF public.payments
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT *
  FROM public.payments 
  WHERE status = 'pending'
  AND scheduled_at < now()
$$;


ALTER FUNCTION public.submittable_payments() OWNER TO postgres;


CREATE FUNCTION public.sync_flows_to_public_circuits() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    latest_record_date timestamptz;
BEGIN
    SELECT COALESCE(MAX(created_at), '2020-01-01'::DATE)
    FROM public.circuits
    INTO latest_record_date;

    INSERT INTO public.circuits (id, type, name, created_at)
    SELECT 
        id, 
        type::text::public.circuit_type_enum, -- cast to replica in public
        name, 
        created_at
    FROM flows.circuits 
    WHERE created_at > latest_record_date;

    SELECT COALESCE(MAX(created_at), '2020-01-01'::DATE)
    FROM public.circuit_meter
    INTO latest_record_date;

    INSERT INTO public.circuit_meter
        SELECT DISTINCT cr.circuit as circuit_id, pm.id as meter_id
        FROM flows.circuit_register cr
        JOIN flows.meter_registers mr ON cr.register = mr.register_id
        JOIN flows.meter_registry reg ON mr.meter_id = reg.id
        JOIN public.meters pm ON reg.serial = pm.serial
        WHERE cr.created_at > latest_record_date;
END;
$$;


ALTER FUNCTION public.sync_flows_to_public_circuits() OWNER TO postgres;


CREATE FUNCTION public.sync_flows_to_public_escos() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO public.escos SELECT * FROM flows.escos where code not in (select code from public.escos);
END;
$$;


ALTER FUNCTION public.sync_flows_to_public_escos() OWNER TO postgres;


CREATE FUNCTION public.sync_flows_to_public_monthly_usage() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    last_synced_month timestamptz;
BEGIN
    SELECT COALESCE(MAX(month), '2020-01-01'::DATE)
    FROM public.monthly_usage
    INTO last_synced_month;

    INSERT INTO public.monthly_usage
        SELECT * FROM flows.circuit_interval_monthly cim
        WHERE cim.month > last_synced_month
    ON CONFLICT (circuit_id, month) DO UPDATE
    SET kwh = EXCLUDED.kwh;
END;
$$;


ALTER FUNCTION public.sync_flows_to_public_monthly_usage() OWNER TO postgres;


CREATE FUNCTION public.topups_payments_check_payment_unique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  existing_count integer;
BEGIN
  SELECT COUNT(*) INTO existing_count 
  FROM public.topups_payments 
  WHERE payment_id = NEW.payment_id;

  IF existing_count > 0 THEN
    RAISE EXCEPTION 'Duplicate payment_id: %. Each payment can only be linked to one topup.', 
                    NEW.payment_id;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.topups_payments_check_payment_unique() OWNER TO postgres;


CREATE FUNCTION public.update_property_tenure() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    affected_properties uuid[];
BEGIN
    -- Determine which properties are affected based on which table triggered the function
    IF TG_TABLE_NAME = 'customer_accounts' THEN
        IF TG_OP = 'DELETE' THEN
            -- For DELETE operations on customer_accounts, use OLD
            SELECT ARRAY_AGG(DISTINCT a.property)
            INTO affected_properties
            FROM public.accounts a
            WHERE a.id = OLD.account;
        ELSE
            -- For INSERT/UPDATE on customer_accounts, use NEW
            SELECT ARRAY_AGG(DISTINCT a.property)
            INTO affected_properties
            FROM public.accounts a
            WHERE a.id = NEW.account;
        END IF;
    ELSIF TG_TABLE_NAME = 'properties' THEN
        -- For properties, just use the specific property ID
        IF TG_OP = 'DELETE' THEN
            affected_properties := ARRAY[OLD.id];
        ELSE
            affected_properties := ARRAY[NEW.id];
        END IF;
    ELSIF TG_TABLE_NAME = 'accounts' THEN
        -- For accounts changes, get property ID from the appropriate record
        IF TG_OP = 'DELETE' THEN
            affected_properties := ARRAY[OLD.property];
        ELSE
            affected_properties := ARRAY[NEW.property];
        END IF;
    END IF;

    -- Update all affected properties
    IF affected_properties IS NOT NULL AND array_length(affected_properties, 1) > 0 THEN
        UPDATE public.properties p
        SET tenure = 
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.accounts a
                    JOIN public.customer_accounts ca ON ca.account = a.id
                    WHERE a.property = p.id
                    AND ca.role = 'occupier'
                    AND ca.customer != p.owner
                ) THEN 'separate_owner_and_occupier'::public.property_tenure_enum
                ELSE 'single_owner_occupier'::public.property_tenure_enum
            END
        WHERE p.id = ANY(affected_properties);
    END IF;
        
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_property_tenure() OWNER TO postgres;


CREATE FUNCTION public.update_solar_credit_applied_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Only proceed if status has changed to 'completed' and used_at has been set
    IF (OLD.status != 'completed' AND NEW.status = 'completed' AND NEW.used_at IS NOT NULL) THEN
        -- Update the applied_at field for any related monthly_solar_credits records
        UPDATE public.monthly_solar_credits msc
        SET applied_at = NEW.used_at
        FROM public.topups_monthly_solar_credits tmsc
        WHERE tmsc.topup_id = NEW.id
        AND tmsc.month_solar_credit_id = msc.id
        AND msc.applied_at IS NULL;
        
        RAISE NOTICE 'Updated applied_at for solar credits linked to topup %', NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_solar_credit_applied_at() OWNER TO postgres;


CREATE FUNCTION public.updated_at_now() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   -- statement_timestamp() NOT now() which is actually transaction_timestamp()
   -- in particular for pg_tap tests the timestamp won't move if using now()
   NEW.updated_at = statement_timestamp(); 
   RETURN NEW;
END;
$$;


ALTER FUNCTION public.updated_at_now() OWNER TO postgres;


CREATE FUNCTION public.validate_allocation_ratio() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if allocation_ratio is NULL or between 0 and 1
    IF NEW.allocation_ratio IS NOT NULL AND 
       (NEW.allocation_ratio < 0 OR NEW.allocation_ratio > 1) THEN
        RAISE EXCEPTION 'Allocation ratio must be between 0 and 1, got %', NEW.allocation_ratio;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_allocation_ratio() OWNER TO postgres;


CREATE FUNCTION public.validate_solar_credit_allocation_ratios() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if the sum of ratios for this installation equals 1
    IF (
        SELECT sum(ratio)
        FROM public.solar_credit_allocation
        WHERE installation_property = NEW.installation_property
    ) > 1 THEN
        RAISE EXCEPTION 'Sum of allocation ratios for an installation cannot exceed 1';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_solar_credit_allocation_ratios() OWNER TO postgres;


CREATE VIEW public.account_contract_meter_flattened AS
 SELECT public.generate_v4_uuid_from_hash(concat(e.code, p.plot, c.email, a.id)) AS id,
    e.code,
    p.plot,
    p.description AS property_description,
    c.email,
    c.fullname,
    c.status AS customer_status,
    ca.role,
    co.type AS contracts_type,
    co.terms AS contracts_terms,
    co.signed_date,
    a.account_number,
    a.id AS account_id,
    a.status AS account_status,
    co.id AS contract_id,
    co.effective_date AS contract_effective_date,
    p.supply_meter,
    m.prepay_enabled AS supply_prepay_enabled,
    m.balance AS supply_meter_balance,
    p.solar_meter,
    c.updated_at AS customer_updated_at
   FROM public.customers c,
    public.customer_accounts ca,
    public.properties p,
    public.escos e,
    public.meters m,
    (public.contracts co
     RIGHT JOIN public.accounts a ON ((a.current_contract = co.id)))
  WHERE ((c.id = ca.customer) AND (ca.account = a.id) AND (a.property = p.id) AND (p.esco = e.id) AND (p.supply_meter = m.id));


ALTER VIEW public.account_contract_meter_flattened OWNER TO postgres;


CREATE VIEW public.property_base_view AS
 SELECT p.id AS property_id,
    e.code AS esco_code,
    p.plot,
    p.description AS property_description,
    p.tenure,
    p.supply_meter,
    p.solar_meter
   FROM (public.properties p
     JOIN public.escos e ON ((p.esco = e.id)));


ALTER VIEW public.property_base_view OWNER TO postgres;


CREATE VIEW public.property_solar_view AS
 SELECT p.property_id,
    a.id AS solar_account_id,
    a.account_number AS solar_account_number,
    a.status AS solar_account_status,
    co.id AS solar_contract_id,
    co.type AS solar_contract_type,
    co.terms AS solar_contract_terms,
    co.signed_date AS solar_signed_date,
    co.effective_date AS solar_contract_effective_date,
    so.fullname AS solar_owner,
    so.email AS solar_owner_email,
    so.status AS solar_owner_status,
    so.updated_at AS solar_owner_updated_at,
    soc.fullname AS solar_occupier,
    soc.email AS solar_occupier_email,
    soc.status AS solar_occupier_status,
    soc.updated_at AS solar_occupier_updated_at
   FROM ((((public.property_base_view p
     LEFT JOIN public.accounts a ON (((p.property_id = a.property) AND (a.type = 'solar'::public.account_type_enum))))
     LEFT JOIN public.contracts co ON ((a.current_contract = co.id)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (public.customer_accounts ca
             JOIN public.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'owner'::public.account_role_type_enum)) so ON ((a.id = so.account)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (public.customer_accounts ca
             JOIN public.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'occupier'::public.account_role_type_enum)) soc ON ((a.id = soc.account)));


ALTER VIEW public.property_solar_view OWNER TO postgres;


CREATE VIEW public.property_supply_view AS
 SELECT p.property_id,
    a.id AS supply_account_id,
    a.account_number AS supply_account_number,
    a.status AS supply_account_status,
    co.id AS supply_contract_id,
    co.type AS supply_contract_type,
    co.terms AS supply_contract_terms,
    co.signed_date AS supply_signed_date,
    co.effective_date AS supply_contract_effective_date,
    so.fullname AS supply_owner,
    so.email AS supply_owner_email,
    so.status AS supply_owner_status,
    so.updated_at AS supply_owner_updated_at,
    soc.fullname AS supply_occupier,
    soc.email AS supply_occupier_email,
    soc.status AS supply_occupier_status,
    soc.updated_at AS supply_occupier_updated_at,
    m.prepay_enabled AS supply_prepay_enabled,
    m.balance AS supply_meter_balance
   FROM (((((public.property_base_view p
     LEFT JOIN public.accounts a ON (((p.property_id = a.property) AND (a.type = 'supply'::public.account_type_enum))))
     LEFT JOIN public.contracts co ON ((a.current_contract = co.id)))
     LEFT JOIN public.meters m ON ((p.supply_meter = m.id)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (public.customer_accounts ca
             JOIN public.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'owner'::public.account_role_type_enum)) so ON ((a.id = so.account)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (public.customer_accounts ca
             JOIN public.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'occupier'::public.account_role_type_enum)) soc ON ((a.id = soc.account)));


ALTER VIEW public.property_supply_view OWNER TO postgres;


CREATE VIEW public.account_contract_meter_row_per_property AS
 SELECT public.generate_v4_uuid_from_hash(concat(b.property_id, p.supply_account_id)) AS id,
    b.property_id,
    b.esco_code,
    b.plot,
    b.property_description,
    b.tenure,
    s.solar_account_id,
    s.solar_account_number,
    s.solar_account_status,
    s.solar_contract_id,
    s.solar_contract_type,
    s.solar_contract_terms,
    s.solar_signed_date,
    s.solar_contract_effective_date,
    s.solar_owner,
    s.solar_owner_email,
    s.solar_owner_status,
    s.solar_occupier,
    s.solar_occupier_email,
    s.solar_occupier_status,
    p.supply_account_id,
    p.supply_account_number,
    p.supply_account_status,
    p.supply_contract_id,
    p.supply_contract_type,
    p.supply_contract_terms,
    p.supply_signed_date,
    p.supply_contract_effective_date,
    p.supply_owner,
    p.supply_owner_email,
    p.supply_owner_status,
    p.supply_occupier,
    p.supply_occupier_email,
    p.supply_occupier_status,
    b.supply_meter,
    p.supply_prepay_enabled,
    p.supply_meter_balance,
    b.solar_meter,
    GREATEST(COALESCE(s.solar_owner_updated_at, '1970-01-01 00:00:00+00'::timestamp with time zone), COALESCE(s.solar_occupier_updated_at, '1970-01-01 00:00:00+00'::timestamp with time zone), COALESCE(p.supply_owner_updated_at, '1970-01-01 00:00:00+00'::timestamp with time zone), COALESCE(p.supply_occupier_updated_at, '1970-01-01 00:00:00+00'::timestamp with time zone)) AS customer_updated_at
   FROM ((public.property_base_view b
     LEFT JOIN public.property_solar_view s ON ((b.property_id = s.property_id)))
     LEFT JOIN public.property_supply_view p ON ((b.property_id = p.property_id)));


ALTER VIEW public.account_contract_meter_row_per_property OWNER TO postgres;


CREATE TABLE public.account_events (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    account uuid NOT NULL,
    history_type public.account_event_type_enum NOT NULL,
    notes text,
    event_timestamp timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);


ALTER TABLE public.account_events OWNER TO postgres;


CREATE TABLE public.benchmark_tariffs (
    period_start date NOT NULL,
    unit_rate numeric NOT NULL,
    standing_charge numeric NOT NULL,
    region text,
    CONSTRAINT benchmark_tariffs_range_check CHECK (((unit_rate >= (0)::numeric) AND (unit_rate <= (100)::numeric) AND ((standing_charge >= (0)::numeric) AND (standing_charge <= (100)::numeric))))
);


ALTER TABLE public.benchmark_tariffs OWNER TO postgres;


COMMENT ON TABLE public.benchmark_tariffs IS 'Energy price cap rates (for direct debit / single rate / southern western region) as published at https://www.ofgem.gov.uk/information-consumers/energy-advice-households/get-energy-price-cap-standing-charges-and-unit-rates-region';



COMMENT ON COLUMN public.benchmark_tariffs.unit_rate IS 'Per kWh rate in pence';



COMMENT ON COLUMN public.benchmark_tariffs.standing_charge IS 'Fixed daily charge in pence';



CREATE VIEW public.customer_supply_status AS
 SELECT public.generate_v4_uuid_from_hash(concat(e.code, p.plot, c.email)) AS id,
    e.code AS esco_code,
    p.plot,
    p.description AS property_description,
    c.email AS customer_email,
    ca.role AS customer_account_role,
    m.prepay_enabled AS supply_meter_prepay_enabled,
    m.balance AS supply_meter_balance,
    c.updated_at AS customer_updated_at,
    p.supply_meter AS supply_meter_id,
    c.fullname AS customer_fullname,
    c.status AS customer_status
   FROM public.customers c,
    public.customer_accounts ca,
    public.properties p,
    public.escos e,
    public.meters m,
    (public.contracts co
     RIGHT JOIN public.accounts a ON ((a.current_contract = co.id)))
  WHERE ((c.id = ca.customer) AND (a.type = 'supply'::public.account_type_enum) AND (ca.account = a.id) AND (a.property = p.id) AND (p.esco = e.id) AND (p.supply_meter = m.id));


ALTER VIEW public.customer_supply_status OWNER TO postgres;


CREATE TABLE public.customer_tariffs (
    customer uuid NOT NULL,
    period_start date NOT NULL,
    discount_rate_basis_points integer NOT NULL,
    computed_unit_rate numeric(6,5),
    computed_standing_charge numeric(6,5),
    CONSTRAINT customer_tariffs_discount_rate_check CHECK (((discount_rate_basis_points >= 0) AND (discount_rate_basis_points <= 100)))
);


ALTER TABLE public.customer_tariffs OWNER TO postgres;


COMMENT ON TABLE public.customer_tariffs IS 'Customer tariffs are computed as a discount on benchmark_tariffs.

The tariffs here should reflect those set on the prepay meters.';



CREATE TABLE public.gifts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    customer_id uuid NOT NULL,
    amount_pence integer NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gifts_amount_check CHECK (((amount_pence > 0) AND (amount_pence <= 30000)))
);


ALTER TABLE public.gifts OWNER TO postgres;


COMMENT ON TABLE public.gifts IS 'Stores gift amounts given to customers';



COMMENT ON COLUMN public.gifts.amount_pence IS 'Gift amount in pence';



COMMENT ON COLUMN public.gifts.reason IS 'Reason for giving the gift';



CREATE VIEW public.meter_tariffs WITH (security_invoker='on') AS
 SELECT DISTINCT e.code AS esco_code,
    ct.period_start,
    m.serial,
    ct.computed_unit_rate AS unit_rate,
    ct.computed_standing_charge AS standing_charge
   FROM public.customer_tariffs ct,
    public.meters m,
    public.properties p,
    public.customer_accounts ca,
    public.accounts a,
    public.escos e
  WHERE ((ct.customer = ca.customer) AND (a.id = ca.account) AND (a.property = p.id) AND (m.id = p.supply_meter) AND (p.esco = e.id));


ALTER VIEW public.meter_tariffs OWNER TO postgres;


CREATE VIEW public.meters_with_incorrect_tariffs WITH (security_invoker='on') AS
 SELECT t.serial,
    t.unit_rate AS expected_unit_rate,
    t.standing_charge AS expected_standing_charge,
    ((s.tariffs_active ->> 'unit_rate_element_a'::text))::numeric AS actual_unit_rate_a,
    ((s.tariffs_active ->> 'unit_rate_element_b'::text))::numeric AS actual_unit_rate_b,
    ((s.tariffs_active ->> 'standing_charge'::text))::numeric AS actual_standing_charge
   FROM public.meter_tariffs t,
    flows.meter_shadows s,
    flows.meter_registry r
  WHERE ((t.serial = r.serial) AND (s.id = r.id) AND (t.period_start = ( SELECT max(td.period_start) AS max
           FROM public.meter_tariffs td
          WHERE ((td.period_start < now()) AND (td.serial = t.serial)))) AND ((((s.tariffs_active ->> 'unit_rate_element_a'::text))::numeric <> t.unit_rate) OR (((s.tariffs_active ->> 'unit_rate_element_b'::text))::numeric <> t.unit_rate) OR (((s.tariffs_active ->> 'standing_charge'::text))::numeric <> t.standing_charge)));


ALTER VIEW public.meters_with_incorrect_tariffs OWNER TO postgres;



ALTER TABLE ONLY public.account_events
    ADD CONSTRAINT account_events_pk PRIMARY KEY (id);



ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.benchmark_tariffs
    ADD CONSTRAINT benchmark_tariffs_pkey PRIMARY KEY (period_start);



ALTER TABLE ONLY public.circuit_meter
    ADD CONSTRAINT circuit_meter_pkey PRIMARY KEY (circuit_id, meter_id);



ALTER TABLE ONLY public.circuits
    ADD CONSTRAINT circuit_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.contract_terms
    ADD CONSTRAINT contract_terms_docuseal_template_id_unique UNIQUE (docuseal_template_id);



ALTER TABLE ONLY public.contract_terms
    ADD CONSTRAINT contract_terms_docuseal_template_slug_unique UNIQUE (docuseal_template_slug);



ALTER TABLE ONLY public.contract_terms
    ADD CONSTRAINT contract_terms_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.customer_accounts
    ADD CONSTRAINT customer_accounts_pkey PRIMARY KEY (customer, account, role);



ALTER TABLE ONLY public.customer_events
    ADD CONSTRAINT customer_events_pkey PRIMARY KEY (customer, event_type, created_at);



ALTER TABLE ONLY public.customer_invites
    ADD CONSTRAINT customer_invites_pkey PRIMARY KEY (invite_token);



ALTER TABLE ONLY public.customer_tariffs
    ADD CONSTRAINT customer_tariffs_pkey PRIMARY KEY (customer, period_start);



ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_email_ukey UNIQUE (email);



ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.escos
    ADD CONSTRAINT escos_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.gifts
    ADD CONSTRAINT gifts_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_serial_unique UNIQUE (serial);



ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_wallet_unique UNIQUE (wallet);



ALTER TABLE ONLY public.microgrid_tariffs
    ADD CONSTRAINT microgrid_tariffs_pkey PRIMARY KEY (esco, period_start);



ALTER TABLE ONLY public.monthly_costs
    ADD CONSTRAINT monthly_costs_pkey PRIMARY KEY (customer_id, month);



ALTER TABLE ONLY public.monthly_solar_credits
    ADD CONSTRAINT monthly_solar_credits_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.monthly_solar_credits
    ADD CONSTRAINT monthly_solar_credits_property_month_unique UNIQUE (property_id, month);



ALTER TABLE ONLY public.monthly_usage
    ADD CONSTRAINT monthly_usage_pkey PRIMARY KEY (circuit_id, month);



ALTER TABLE ONLY public.places
    ADD CONSTRAINT nested_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.payment_events
    ADD CONSTRAINT payment_events_pk PRIMARY KEY (payment, event_type, created_at);



ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_account_created_at_unique UNIQUE (account, created_at);



ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.postgres_notifications
    ADD CONSTRAINT postgres_notifications_pkey PRIMARY KEY (channel, payload, created_at);



ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.regions
    ADD CONSTRAINT region_pkey PRIMARY KEY (code);



ALTER TABLE ONLY public.regions
    ADD CONSTRAINT region_unique UNIQUE (name);



ALTER TABLE ONLY public.solar_credit_allocation
    ADD CONSTRAINT solar_credit_allocation_pkey PRIMARY KEY (installation_property, allocation_property);



ALTER TABLE ONLY public.solar_credit_tariffs
    ADD CONSTRAINT solar_credit_tariffs_pkey PRIMARY KEY (esco, period_start);



ALTER TABLE ONLY public.solar_installation
    ADD CONSTRAINT solar_installation_mcs_unique UNIQUE (mcs);



ALTER TABLE ONLY public.solar_installation
    ADD CONSTRAINT solar_installation_pkey PRIMARY KEY (property);



ALTER TABLE ONLY public.topup_events
    ADD CONSTRAINT topup_events_pkey PRIMARY KEY (topup);



ALTER TABLE ONLY public.topups
    ADD CONSTRAINT topups_meter_created_at_unique UNIQUE (meter, created_at);



ALTER TABLE ONLY public.topups_monthly_solar_credits
    ADD CONSTRAINT topups_monthly_solar_credits_month_solar_credit_id_unique UNIQUE (month_solar_credit_id);



ALTER TABLE ONLY public.topups_monthly_solar_credits
    ADD CONSTRAINT topups_monthly_solar_credits_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.topups_payments
    ADD CONSTRAINT topups_payments_pkey PRIMARY KEY (payment_id, topup_id);



ALTER TABLE ONLY public.topups
    ADD CONSTRAINT topups_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);



CREATE INDEX accounts_current_contract_idx ON public.accounts USING btree (current_contract);



CREATE INDEX accounts_property_idx ON public.accounts USING btree (property);



CREATE INDEX benchmark_tariffs_region_idx ON public.benchmark_tariffs USING btree (region);



CREATE INDEX circuit_meter_meter_idx ON public.circuit_meter USING btree (meter_id);



CREATE INDEX contracts_terms_idx ON public.contracts USING btree (terms);



CREATE INDEX customer_accounts_account_idx ON public.customer_accounts USING btree (account);



CREATE INDEX customer_invites_customer_idx ON public.customer_invites USING btree (customer);



CREATE INDEX escos_region_idx ON public.escos USING btree (region);



CREATE INDEX properties_esco_idx ON public.properties USING btree (esco);



CREATE INDEX properties_owner_idx ON public.properties USING btree (owner);



CREATE INDEX properties_site_idx ON public.properties USING btree (site);



CREATE INDEX properties_solar_meter_idx ON public.properties USING btree (solar_meter);



CREATE INDEX properties_supply_meter_idx ON public.properties USING btree (supply_meter);



CREATE INDEX solar_credit_tariffs_period_start_idx ON public.solar_credit_tariffs USING btree (period_start);



CREATE CONSTRAINT TRIGGER account_current_contract_update_trigger AFTER UPDATE OF current_contract ON public.accounts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.accounts_current_contract_update_customer_status_trigger();



CREATE TRIGGER accounts_contract_update AFTER UPDATE OF current_contract ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.account_check_contract_terms_and_esco();



CREATE TRIGGER accounts_generate_name_on_update_trigger AFTER INSERT OR UPDATE OF type, property ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.accounts_generate_name_for_trigger();



CREATE TRIGGER accounts_updated_at BEFORE UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER benchmark_tariffs_generate_tariffs_trigger AFTER INSERT OR UPDATE ON public.benchmark_tariffs FOR EACH ROW EXECUTE FUNCTION public.benchmark_tariffs_generate_tariffs();



COMMENT ON TRIGGER benchmark_tariffs_generate_tariffs_trigger ON public.benchmark_tariffs IS 'Trigger that automatically generates customer and microgrid tariffs when a new benchmark tariff is added or an existing one is updated.
This ensures that all tariff tables remain in sync with benchmark tariffs.';



CREATE TRIGGER check_solar_credit_allocation_ratios AFTER INSERT OR UPDATE ON public.solar_credit_allocation FOR EACH ROW EXECUTE FUNCTION public.validate_solar_credit_allocation_ratios();



CREATE TRIGGER check_unique_properties_meters BEFORE INSERT OR UPDATE ON public.properties FOR EACH ROW EXECUTE FUNCTION public.check_unique_properties_meters();



CREATE TRIGGER contract_terms_updated_at BEFORE UPDATE ON public.contract_terms FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER contract_update_terms AFTER UPDATE OF terms ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.contract_check_contract_terms_and_esco();



CREATE TRIGGER contracts_signed_date_update_trigger AFTER UPDATE OF signed_date ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.contracts_signed_update_customer_status();



CREATE TRIGGER contracts_updated_at BEFORE UPDATE ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER customer_accounts_updated_at BEFORE UPDATE ON public.customer_accounts FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER customer_invites_generate_invite_url_on_insert_or_update BEFORE INSERT OR UPDATE ON public.customer_invites FOR EACH ROW EXECUTE FUNCTION public.customer_invites_generate_invite_url();



CREATE TRIGGER customer_status_update BEFORE UPDATE OF exiting, has_payment_method, confirmed_details_at, allow_onboard_transition ON public.customers FOR EACH ROW EXECUTE FUNCTION public.customer_status_update_on_trigger();



CREATE TRIGGER customer_update_log_trigger AFTER UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.customer_update_log_on_trigger();



CREATE TRIGGER customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER gifts_updated_at BEFORE UPDATE ON public.gifts FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE CONSTRAINT TRIGGER meter_prepay_status_change_trigger AFTER UPDATE OF prepay_enabled ON public.meters DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((old.prepay_enabled IS DISTINCT FROM new.prepay_enabled)) EXECUTE FUNCTION public.meter_prepay_status_change();



CREATE TRIGGER meters_updated_at BEFORE UPDATE ON public.meters FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER monthly_costs_compute_totals_on_insert_or_update BEFORE INSERT OR UPDATE ON public.monthly_costs FOR EACH ROW EXECUTE FUNCTION public.monthly_costs_compute_totals();



CREATE TRIGGER monthly_costs_updated_at BEFORE UPDATE ON public.monthly_costs FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER monthly_solar_credits_compute_credit_trigger BEFORE INSERT OR UPDATE OF month, property_id ON public.monthly_solar_credits FOR EACH ROW EXECUTE FUNCTION public.monthly_solar_credits_compute_credit();



CREATE TRIGGER monthly_solar_credits_ratio_validation BEFORE INSERT OR UPDATE OF allocation_ratio ON public.monthly_solar_credits FOR EACH ROW EXECUTE FUNCTION public.validate_allocation_ratio();



CREATE TRIGGER monthly_solar_credits_updated_at BEFORE UPDATE ON public.monthly_solar_credits FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER payment_insert_log_trigger AFTER INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION public.payment_insert_log_on_trigger();



CREATE TRIGGER payment_update_log_trigger AFTER UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.payment_update_log_on_trigger();



CREATE TRIGGER payments_updated_at BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER properties_updated_at BEFORE UPDATE ON public.properties FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER solar_credit_allocation_updated_at BEFORE UPDATE ON public.solar_credit_allocation FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER solar_credit_tariffs_compute_daily_credit_trigger BEFORE INSERT OR UPDATE OF credit_pence_per_year, period_start ON public.solar_credit_tariffs FOR EACH ROW EXECUTE FUNCTION public.solar_credit_tariffs_compute_daily_credit();



CREATE TRIGGER solar_credit_tariffs_updated_at BEFORE UPDATE ON public.solar_credit_tariffs FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER solar_installation_updated_at BEFORE UPDATE ON public.solar_installation FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER tariffs_customer_discount_rate_basis_points_insert_or_update BEFORE INSERT OR UPDATE OF discount_rate_basis_points ON public.customer_tariffs FOR EACH ROW EXECUTE FUNCTION public.customer_tariffs_compute_rates();



CREATE TRIGGER tariffs_microgrid_discount_rate_basis_points_insert_or_update BEFORE INSERT OR UPDATE OF discount_rate_basis_points ON public.microgrid_tariffs FOR EACH ROW EXECUTE FUNCTION public.microgrid_tariffs_compute_rates();



CREATE TRIGGER topups_payments_check_payment_unique_trigger BEFORE INSERT ON public.topups_payments FOR EACH ROW EXECUTE FUNCTION public.topups_payments_check_payment_unique();



CREATE TRIGGER topups_update_solar_credit_applied_at AFTER UPDATE OF status, used_at ON public.topups FOR EACH ROW EXECUTE FUNCTION public.update_solar_credit_applied_at();



CREATE TRIGGER topups_updated_at BEFORE UPDATE ON public.topups FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



CREATE TRIGGER update_property_tenure_accounts AFTER INSERT OR DELETE OR UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.update_property_tenure();



CREATE TRIGGER update_property_tenure_customer_accounts AFTER INSERT OR DELETE OR UPDATE ON public.customer_accounts FOR EACH ROW EXECUTE FUNCTION public.update_property_tenure();



CREATE TRIGGER update_property_tenure_properties AFTER UPDATE OF owner ON public.properties FOR EACH ROW EXECUTE FUNCTION public.update_property_tenure();



CREATE TRIGGER wallets_updated_at BEFORE UPDATE ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.updated_at_now();



ALTER TABLE ONLY public.account_events
    ADD CONSTRAINT account_events_account_fkey FOREIGN KEY (account) REFERENCES public.accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_contract_fkey FOREIGN KEY (current_contract) REFERENCES public.contracts(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_property_fkey FOREIGN KEY (property) REFERENCES public.properties(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.benchmark_tariffs
    ADD CONSTRAINT benchmark_tariffs_region_fkey FOREIGN KEY (region) REFERENCES public.regions(code) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.circuit_meter
    ADD CONSTRAINT circuit_meter_circuit_fkey FOREIGN KEY (circuit_id) REFERENCES public.circuits(id);



ALTER TABLE ONLY public.circuit_meter
    ADD CONSTRAINT circuit_meter_meter_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);



ALTER TABLE ONLY public.contract_terms_esco
    ADD CONSTRAINT contract_terms_esco_esco_fkey FOREIGN KEY (esco) REFERENCES public.escos(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.contract_terms_esco
    ADD CONSTRAINT contract_terms_esco_terms_fkey FOREIGN KEY (terms) REFERENCES public.contract_terms(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_contract_terms_fkey FOREIGN KEY (terms) REFERENCES public.contract_terms(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE;



ALTER TABLE ONLY public.customer_accounts
    ADD CONSTRAINT customer_accounts_account_fkey FOREIGN KEY (account) REFERENCES public.accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.customer_accounts
    ADD CONSTRAINT customer_accounts_customer_fkey FOREIGN KEY (customer) REFERENCES public.customers(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.customer_events
    ADD CONSTRAINT customer_events_customers_fkey FOREIGN KEY (customer) REFERENCES public.customers(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.customer_invites
    ADD CONSTRAINT customer_invites_customer_fkey FOREIGN KEY (customer) REFERENCES public.customers(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.customer_tariffs
    ADD CONSTRAINT customer_tariffs_customer_fkey FOREIGN KEY (customer) REFERENCES public.customers(id);



ALTER TABLE ONLY public.escos
    ADD CONSTRAINT esco_region_fkey FOREIGN KEY (region) REFERENCES public.regions(code) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.gifts
    ADD CONSTRAINT gifts_customer_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_wallet_fkey FOREIGN KEY (wallet) REFERENCES public.wallets(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.microgrid_tariffs
    ADD CONSTRAINT microgrid_tariffs_esco_fkey FOREIGN KEY (esco) REFERENCES public.escos(id);



ALTER TABLE ONLY public.monthly_costs
    ADD CONSTRAINT monthly_costs_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);



ALTER TABLE ONLY public.monthly_solar_credits
    ADD CONSTRAINT monthly_solar_credits_property_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.monthly_solar_credits
    ADD CONSTRAINT monthly_solar_credits_source_installation_fkey FOREIGN KEY (source_installation) REFERENCES public.properties(id);



ALTER TABLE ONLY public.monthly_usage
    ADD CONSTRAINT monthly_usage_circuits_fkey FOREIGN KEY (circuit_id) REFERENCES public.circuits(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.payment_events
    ADD CONSTRAINT payment_events_payments_fkey FOREIGN KEY (payment) REFERENCES public.payments(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_account_fkey FOREIGN KEY (account) REFERENCES public.accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_esco_fkey FOREIGN KEY (esco) REFERENCES public.escos(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_owner_fkey FOREIGN KEY (owner) REFERENCES public.customers(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_solar_meter_fkey FOREIGN KEY (solar_meter) REFERENCES public.meters(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_supply_meter_fkey FOREIGN KEY (supply_meter) REFERENCES public.meters(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.solar_credit_allocation
    ADD CONSTRAINT solar_credit_allocation_allocation_property_fkey FOREIGN KEY (allocation_property) REFERENCES public.properties(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.solar_credit_allocation
    ADD CONSTRAINT solar_credit_allocation_installation_property_fkey FOREIGN KEY (installation_property) REFERENCES public.properties(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.solar_credit_tariffs
    ADD CONSTRAINT solar_credit_tariffs_esco_fkey FOREIGN KEY (esco) REFERENCES public.escos(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.solar_installation
    ADD CONSTRAINT solar_installation_property_fkey FOREIGN KEY (property) REFERENCES public.properties(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.topup_events
    ADD CONSTRAINT topup_events_topups_fkey FOREIGN KEY (topup) REFERENCES public.topups(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.topups
    ADD CONSTRAINT topups_meter_fkey FOREIGN KEY (meter) REFERENCES public.meters(id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY public.topups_monthly_solar_credits
    ADD CONSTRAINT topups_monthly_solar_credits_month_solar_credit_id_fkey FOREIGN KEY (month_solar_credit_id) REFERENCES public.monthly_solar_credits(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.topups_monthly_solar_credits
    ADD CONSTRAINT topups_monthly_solar_credits_topup_fkey FOREIGN KEY (topup_id) REFERENCES public.topups(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.topups_payments
    ADD CONSTRAINT topups_payments_payment_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



ALTER TABLE ONLY public.topups_payments
    ADD CONSTRAINT topups_payments_topup_fkey FOREIGN KEY (topup_id) REFERENCES public.topups(id) ON UPDATE RESTRICT ON DELETE RESTRICT;



CREATE POLICY "Authenticated users can read microgrid tariffs" ON public.microgrid_tariffs FOR SELECT TO authenticated USING ((esco IN ( SELECT p.esco
   FROM public.properties p
  WHERE (p.id IN ( SELECT a.property
           FROM public.accounts a,
            public.customer_accounts ca
          WHERE ((ca.customer = public.customer()) AND (a.id = ca.account)))))));



CREATE POLICY "Authenticated users can read solar credit tariffs" ON public.solar_credit_tariffs FOR SELECT TO authenticated USING ((esco IN ( SELECT p.esco
   FROM public.properties p
  WHERE (p.id IN ( SELECT a.property
           FROM public.accounts a,
            public.customer_accounts ca
          WHERE ((ca.customer = public.customer()) AND (a.id = ca.account)))))));



CREATE POLICY "Authenticated users can read tariffs" ON public.benchmark_tariffs FOR SELECT TO authenticated USING (true);



CREATE POLICY "Authenticated users can read their customer_tariffs only" ON public.customer_tariffs FOR SELECT TO authenticated USING ((customer = public.customer()));



CREATE POLICY "Customer can view solar installations for their properties" ON public.solar_installation FOR SELECT TO authenticated USING ((property IN ( SELECT properties.id
   FROM public.properties)));



CREATE POLICY "Customer can view their own meters" ON public.meters FOR SELECT TO authenticated USING ((id IN ( SELECT properties.supply_meter
   FROM public.properties
UNION
 SELECT properties.solar_meter
   FROM public.properties)));



CREATE POLICY "Customers can read their own and property owners records" ON public.customers FOR SELECT TO authenticated USING (((email = auth.email()) OR (id IN ( SELECT public.get_property_owners_for_auth_user(auth.email()) AS get_property_owners_for_auth_user))));



CREATE POLICY "Customers can update their wallets topup preferences only" ON public.wallets FOR UPDATE TO authenticated USING ((id IN ( SELECT meters.wallet
   FROM public.meters
  WHERE (meters.id IN ( SELECT properties.supply_meter
           FROM public.properties
          WHERE (properties.id IN ( SELECT accounts.property
                   FROM public.accounts)))))));



CREATE POLICY "Customers can view their own accounts only" ON public.accounts FOR SELECT TO authenticated USING ((id IN ( SELECT customer_accounts.account
   FROM public.customer_accounts)));



CREATE POLICY "Customers can view their own circuit_meter records only" ON public.circuit_meter FOR SELECT TO authenticated USING ((meter_id IN ( SELECT meters.id
   FROM public.meters)));



CREATE POLICY "Customers can view their own circuits only" ON public.circuits FOR SELECT TO authenticated USING ((id IN ( SELECT circuit_meter.circuit_id
   FROM public.circuit_meter)));



CREATE POLICY "Customers can view their own contracts only" ON public.contracts FOR SELECT TO authenticated USING ((id IN ( SELECT accounts.current_contract
   FROM public.accounts
  WHERE (accounts.id = ANY (public.accounts())))));



CREATE POLICY "Customers can view their own customer_accounts" ON public.customer_accounts FOR SELECT TO authenticated USING ((customer = public.customer()));



CREATE POLICY "Customers can view their own gifts" ON public.gifts FOR SELECT TO authenticated USING ((customer_id = public.customer()));



CREATE POLICY "Customers can view their own monthly customer costs only" ON public.monthly_costs FOR SELECT TO authenticated USING ((customer_id = public.customer()));



CREATE POLICY "Customers can view their own monthly solar credits" ON public.monthly_solar_credits FOR SELECT TO authenticated USING ((property_id IN ( SELECT a.property
   FROM public.accounts a
  WHERE (a.id IN ( SELECT ca.account
           FROM public.customer_accounts ca
          WHERE (ca.customer = public.customer()))))));



CREATE POLICY "Customers can view their own monthly usage only" ON public.monthly_usage FOR SELECT TO authenticated USING ((circuit_id IN ( SELECT circuits.id
   FROM public.circuits)));



CREATE POLICY "Customers can view their own payment topups" ON public.topups_payments FOR SELECT TO authenticated USING ((payment_id IN ( SELECT p.id
   FROM ((public.payments p
     JOIN public.accounts a ON ((p.account = a.id)))
     JOIN public.customer_accounts ca ON ((ca.account = a.id)))
  WHERE (ca.customer = public.customer()))));



CREATE POLICY "Customers can view their own payments only" ON public.payments USING ((account IN ( SELECT customer_accounts.account
   FROM public.customer_accounts
  WHERE (customer_accounts.customer = public.customer()))));



CREATE POLICY "Customers can view their own properties or all if cepro user" ON public.properties FOR SELECT TO authenticated USING (((id = ANY (public.properties_by_account())) OR (id = ANY (public.properties_owned())) OR (EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.email = auth.email()) AND (customers.cepro_user = true))))));



CREATE POLICY "Customers can view their own solar credits topups" ON public.topups_monthly_solar_credits FOR SELECT TO authenticated USING ((month_solar_credit_id IN ( SELECT m.id
   FROM ((public.monthly_solar_credits m
     JOIN public.accounts a ON ((a.property = m.property_id)))
     JOIN public.customer_accounts ca ON ((ca.account = a.id)))
  WHERE (ca.customer = public.customer()))));



CREATE POLICY "Customers can view their own topups only" ON public.topups USING ((meter IN ( SELECT meters.id
   FROM public.meters)));



CREATE POLICY "Customers can view their own wallets only" ON public.wallets FOR SELECT TO authenticated USING ((id IN ( SELECT meters.wallet
   FROM public.meters
  WHERE (meters.id IN ( SELECT properties.supply_meter
           FROM public.properties
          WHERE (properties.id IN ( SELECT accounts.property
                   FROM public.accounts
                  WHERE (accounts.id = ANY (public.accounts())))))))));



CREATE POLICY "Enable read access for all users" ON public.escos FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON public.regions FOR SELECT USING (true);



CREATE POLICY "Users can see term escos mappings for escos they have accounts " ON public.contract_terms_esco FOR SELECT TO authenticated USING ((esco IN ( SELECT properties.esco
   FROM public.properties
  WHERE (properties.id IN ( SELECT accounts.property
           FROM public.accounts
          WHERE (accounts.id IN ( SELECT ca.account
                   FROM public.customer_accounts ca
                  WHERE (ca.customer = public.customer()))))))));



CREATE POLICY "Users can see terms for escos they have accounts in or all if c" ON public.contract_terms FOR SELECT TO authenticated USING (((id IN ( SELECT contract_terms_esco.terms
   FROM public.contract_terms_esco)) OR (EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.email = auth.email()) AND (customers.cepro_user = true))))));



ALTER TABLE public.account_events ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.benchmark_tariffs ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.circuit_meter ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.circuits ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.contract_terms ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.contract_terms_esco ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.customer_accounts ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.customer_events ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.customer_invites ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.customer_tariffs ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.escos ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.gifts ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grafanareader role can read all for alert checking" ON public.microgrid_tariffs TO grafanareader USING (true);



CREATE POLICY "grafanareader role can read all for alert checking" ON public.solar_credit_tariffs TO grafanareader USING (true);



ALTER TABLE public.meters ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.microgrid_tariffs ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.monthly_costs ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.monthly_solar_credits ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.monthly_usage ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.places ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.postgres_notifications ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.solar_credit_tariffs ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.solar_installation ENABLE ROW LEVEL SECURITY;


CREATE POLICY "supabase_auth_admin can read all" ON public.customers FOR SELECT TO supabase_auth_admin USING (true);



ALTER TABLE public.topup_events ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.topups ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.topups_monthly_solar_credits ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.topups_payments ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.transaction_statuses ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA flows TO public_backend;



GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA public TO public_backend;
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT USAGE ON SCHEMA public TO grafanareader;



GRANT ALL ON FUNCTION public.accounts() TO anon;
GRANT ALL ON FUNCTION public.accounts() TO authenticated;
GRANT ALL ON FUNCTION public.accounts() TO service_role;



GRANT ALL ON FUNCTION public.benchmark_month_standing_charge(region_in text, month_in date) TO anon;
GRANT ALL ON FUNCTION public.benchmark_month_standing_charge(region_in text, month_in date) TO authenticated;
GRANT ALL ON FUNCTION public.benchmark_month_standing_charge(region_in text, month_in date) TO service_role;



GRANT ALL ON FUNCTION public.benchmark_unit_rate(region_in text, month_in date) TO anon;
GRANT ALL ON FUNCTION public.benchmark_unit_rate(region_in text, month_in date) TO authenticated;
GRANT ALL ON FUNCTION public.benchmark_unit_rate(region_in text, month_in date) TO service_role;



GRANT ALL ON FUNCTION public.change_property_owner(property_id uuid, new_owner uuid) TO anon;
GRANT ALL ON FUNCTION public.change_property_owner(property_id uuid, new_owner uuid) TO authenticated;
GRANT ALL ON FUNCTION public.change_property_owner(property_id uuid, new_owner uuid) TO service_role;



GRANT ALL ON FUNCTION public.check_property_setup(property_id uuid) TO anon;
GRANT ALL ON FUNCTION public.check_property_setup(property_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.check_property_setup(property_id uuid) TO service_role;



GRANT ALL ON FUNCTION public.check_unique_properties_meters() TO anon;
GRANT ALL ON FUNCTION public.check_unique_properties_meters() TO authenticated;
GRANT ALL ON FUNCTION public.check_unique_properties_meters() TO service_role;



GRANT ALL ON FUNCTION public.circuits() TO anon;
GRANT ALL ON FUNCTION public.circuits() TO authenticated;
GRANT ALL ON FUNCTION public.circuits() TO service_role;



GRANT ALL ON FUNCTION public.create_user(email text, password text) TO service_role;



GRANT ALL ON FUNCTION public.customer_invites_generate_invite_url() TO anon;
GRANT ALL ON FUNCTION public.customer_invites_generate_invite_url() TO authenticated;
GRANT ALL ON FUNCTION public.customer_invites_generate_invite_url() TO service_role;



GRANT ALL ON FUNCTION public.customer_invites_insert_from_customer() TO anon;
GRANT ALL ON FUNCTION public.customer_invites_insert_from_customer() TO authenticated;
GRANT ALL ON FUNCTION public.customer_invites_insert_from_customer() TO service_role;



GRANT ALL ON FUNCTION public.customer_invites_status(accessed_at timestamp with time zone, expires_at timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION public.customer_invites_status(accessed_at timestamp with time zone, expires_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.customer_invites_status(accessed_at timestamp with time zone, expires_at timestamp with time zone) TO service_role;



GRANT ALL ON FUNCTION public.customer_jwt_token_hook(event jsonb) TO service_role;
GRANT ALL ON FUNCTION public.customer_jwt_token_hook(event jsonb) TO supabase_auth_admin;



GRANT ALL ON FUNCTION public.customer_registration() TO anon;
GRANT ALL ON FUNCTION public.customer_registration() TO authenticated;
GRANT ALL ON FUNCTION public.customer_registration() TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customers TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customers TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customers TO service_role;
GRANT SELECT,UPDATE ON TABLE public.customers TO public_backend;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customers TO supabase_auth_admin;



GRANT ALL ON FUNCTION public.customer_status_update_on_auth_users_trigger() TO anon;
GRANT ALL ON FUNCTION public.customer_status_update_on_auth_users_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.customer_status_update_on_auth_users_trigger() TO service_role;



GRANT ALL ON FUNCTION public.customer_status_update_on_trigger() TO anon;
GRANT ALL ON FUNCTION public.customer_status_update_on_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.customer_status_update_on_trigger() TO service_role;



GRANT ALL ON FUNCTION public.customer_tariffs_compute_rates() TO anon;
GRANT ALL ON FUNCTION public.customer_tariffs_compute_rates() TO authenticated;
GRANT ALL ON FUNCTION public.customer_tariffs_compute_rates() TO service_role;



GRANT ALL ON FUNCTION public.customer_tariffs_create_all_for_month(month_in date, discount_rate_in integer) TO anon;
GRANT ALL ON FUNCTION public.customer_tariffs_create_all_for_month(month_in date, discount_rate_in integer) TO authenticated;
GRANT ALL ON FUNCTION public.customer_tariffs_create_all_for_month(month_in date, discount_rate_in integer) TO service_role;



GRANT ALL ON FUNCTION public.days_in_month(month_in date) TO anon;
GRANT ALL ON FUNCTION public.days_in_month(month_in date) TO authenticated;
GRANT ALL ON FUNCTION public.days_in_month(month_in date) TO service_role;



GRANT ALL ON FUNCTION public.delete_customer(customer_email text) TO anon;
GRANT ALL ON FUNCTION public.delete_customer(customer_email text) TO authenticated;
GRANT ALL ON FUNCTION public.delete_customer(customer_email text) TO service_role;



GRANT ALL ON FUNCTION public.delete_property_and_customers(property_id uuid) TO anon;
GRANT ALL ON FUNCTION public.delete_property_and_customers(property_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_property_and_customers(property_id uuid) TO service_role;



GRANT ALL ON FUNCTION public.generate_random_meter_serial() TO anon;
GRANT ALL ON FUNCTION public.generate_random_meter_serial() TO authenticated;
GRANT ALL ON FUNCTION public.generate_random_meter_serial() TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contract_terms TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contract_terms TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contract_terms TO service_role;
GRANT SELECT ON TABLE public.contract_terms TO public_backend;



GRANT ALL ON FUNCTION public.log_array_of_uuid(uuids uuid[], label text) TO anon;
GRANT ALL ON FUNCTION public.log_array_of_uuid(uuids uuid[], label text) TO authenticated;
GRANT ALL ON FUNCTION public.log_array_of_uuid(uuids uuid[], label text) TO service_role;



GRANT SELECT,INSERT,UPDATE ON TABLE public.payments TO public_backend;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payments TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payments TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payments TO service_role;
GRANT SELECT ON TABLE public.payments TO grafanareader;



GRANT ALL ON FUNCTION public.meters_with_unsynced_emergency_credit_settings(esco_filter text) TO anon;
GRANT ALL ON FUNCTION public.meters_with_unsynced_emergency_credit_settings(esco_filter text) TO authenticated;
GRANT ALL ON FUNCTION public.meters_with_unsynced_emergency_credit_settings(esco_filter text) TO service_role;



GRANT ALL ON FUNCTION public.microgrid_month_standing_charge(esco_code_in text, month_in date) TO anon;
GRANT ALL ON FUNCTION public.microgrid_month_standing_charge(esco_code_in text, month_in date) TO authenticated;
GRANT ALL ON FUNCTION public.microgrid_month_standing_charge(esco_code_in text, month_in date) TO service_role;



GRANT ALL ON FUNCTION public.microgrid_tariffs_compute_rates() TO anon;
GRANT ALL ON FUNCTION public.microgrid_tariffs_compute_rates() TO authenticated;
GRANT ALL ON FUNCTION public.microgrid_tariffs_compute_rates() TO service_role;



GRANT ALL ON FUNCTION public.microgrid_unit_rate(esco_code_in text, month_in date) TO anon;
GRANT ALL ON FUNCTION public.microgrid_unit_rate(esco_code_in text, month_in date) TO authenticated;
GRANT ALL ON FUNCTION public.microgrid_unit_rate(esco_code_in text, month_in date) TO service_role;



GRANT ALL ON FUNCTION public.monthly_costs_compute_totals() TO anon;
GRANT ALL ON FUNCTION public.monthly_costs_compute_totals() TO authenticated;
GRANT ALL ON FUNCTION public.monthly_costs_compute_totals() TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_solar_credits TO authenticated;
GRANT SELECT ON TABLE public.monthly_solar_credits TO public_backend;
GRANT SELECT ON TABLE public.monthly_solar_credits TO grafanareader;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_solar_credits TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_solar_credits TO service_role;



GRANT ALL ON FUNCTION public.properties_by_account() TO anon;
GRANT ALL ON FUNCTION public.properties_by_account() TO authenticated;
GRANT ALL ON FUNCTION public.properties_by_account() TO service_role;



GRANT ALL ON FUNCTION public.properties_owned() TO anon;
GRANT ALL ON FUNCTION public.properties_owned() TO authenticated;
GRANT ALL ON FUNCTION public.properties_owned() TO service_role;



GRANT ALL ON FUNCTION public.sync_flows_to_public_circuits() TO anon;
GRANT ALL ON FUNCTION public.sync_flows_to_public_circuits() TO authenticated;
GRANT ALL ON FUNCTION public.sync_flows_to_public_circuits() TO service_role;



GRANT ALL ON FUNCTION public.sync_flows_to_public_escos() TO anon;
GRANT ALL ON FUNCTION public.sync_flows_to_public_escos() TO authenticated;
GRANT ALL ON FUNCTION public.sync_flows_to_public_escos() TO service_role;



GRANT ALL ON FUNCTION public.sync_flows_to_public_monthly_usage() TO anon;
GRANT ALL ON FUNCTION public.sync_flows_to_public_monthly_usage() TO authenticated;
GRANT ALL ON FUNCTION public.sync_flows_to_public_monthly_usage() TO service_role;



GRANT ALL ON FUNCTION public.updated_at_now() TO anon;
GRANT ALL ON FUNCTION public.updated_at_now() TO authenticated;
GRANT ALL ON FUNCTION public.updated_at_now() TO service_role;


GRANT SELECT ON TABLE flows.meter_registry TO public_backend;
GRANT SELECT ON TABLE flows.meter_shadows TO public_backend;
GRANT SELECT ON TABLE flows.meter_shadows_tariffs TO public_backend;


GRANT ALL ON SEQUENCE public.account_number_seq TO anon;
GRANT ALL ON SEQUENCE public.account_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.account_number_seq TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.accounts TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.accounts TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.accounts TO service_role;
GRANT SELECT ON TABLE public.accounts TO public_backend;
GRANT SELECT ON TABLE public.accounts TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contracts TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contracts TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contracts TO service_role;
GRANT SELECT,UPDATE ON TABLE public.contracts TO public_backend;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_accounts TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_accounts TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_accounts TO service_role;
GRANT SELECT ON TABLE public.customer_accounts TO public_backend;
GRANT SELECT ON TABLE public.customer_accounts TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.escos TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.escos TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.escos TO service_role;
GRANT SELECT ON TABLE public.escos TO public_backend;
GRANT SELECT ON TABLE public.escos TO flows;
GRANT SELECT ON TABLE public.escos TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.meters TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.meters TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.meters TO service_role;
GRANT SELECT ON TABLE public.meters TO public_backend;
GRANT SELECT ON TABLE public.meters TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.properties TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.properties TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.properties TO service_role;
GRANT SELECT ON TABLE public.properties TO public_backend;
GRANT SELECT ON TABLE public.properties TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.account_events TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.account_events TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.account_events TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.benchmark_tariffs TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.benchmark_tariffs TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.benchmark_tariffs TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.circuit_meter TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.circuit_meter TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.circuit_meter TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.circuits TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.circuits TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.circuits TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.contract_terms_esco TO authenticated;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_invites TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_invites TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_invites TO service_role;
GRANT SELECT,UPDATE ON TABLE public.customer_invites TO public_backend;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_tariffs TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_tariffs TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.customer_tariffs TO service_role;
GRANT SELECT ON TABLE public.customer_tariffs TO public_backend;
GRANT SELECT ON TABLE public.customer_tariffs TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.gifts TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.gifts TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.gifts TO service_role;
GRANT SELECT ON TABLE public.gifts TO public_backend;



GRANT SELECT ON TABLE public.meter_tariffs TO grafanareader;
GRANT SELECT ON TABLE public.meter_tariffs TO public_backend;



GRANT SELECT ON TABLE public.meters_with_incorrect_tariffs TO grafanareader;
GRANT SELECT ON TABLE public.meters_with_incorrect_tariffs TO flows;
GRANT SELECT ON TABLE public.meters_with_incorrect_tariffs TO public_backend;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.microgrid_tariffs TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.microgrid_tariffs TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.microgrid_tariffs TO service_role;
GRANT SELECT ON TABLE public.microgrid_tariffs TO public_backend;
GRANT SELECT ON TABLE public.microgrid_tariffs TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_costs TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_costs TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_costs TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_usage TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_usage TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.monthly_usage TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.places TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.places TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.places TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.regions TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.regions TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.regions TO service_role;



GRANT SELECT ON TABLE public.solar_credit_tariffs TO authenticated;
GRANT SELECT ON TABLE public.solar_credit_tariffs TO public_backend;
GRANT SELECT ON TABLE public.solar_credit_tariffs TO grafanareader;



GRANT SELECT,INSERT,UPDATE ON TABLE public.solar_installation TO public_backend;
GRANT SELECT,INSERT,UPDATE ON TABLE public.solar_installation TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE public.solar_installation TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE public.solar_installation TO service_role;



GRANT SELECT,INSERT,UPDATE ON TABLE public.topups TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE public.topups TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE public.topups TO service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE public.topups TO public_backend;
GRANT SELECT ON TABLE public.topups TO grafanareader;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_monthly_solar_credits TO public_backend;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_monthly_solar_credits TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_monthly_solar_credits TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_monthly_solar_credits TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_payments TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_payments TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_payments TO service_role;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.topups_payments TO public_backend;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.transaction_statuses TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.transaction_statuses TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.transaction_statuses TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.transactions TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.transactions TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.transactions TO service_role;



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.wallets TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.wallets TO authenticated;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.wallets TO service_role;



ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA flows GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO flows;



ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;



ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;



ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO postgres;
