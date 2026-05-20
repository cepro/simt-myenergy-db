-- Deploy supabase:0021_corporate_bodies_grants to pg
-- Enable RLS on registered_proprietors and grant access similar to properties table

BEGIN;

-- Add timestamps to corporate_bodies
ALTER TABLE myenergy.corporate_bodies
    ADD COLUMN created_at timestamp with time zone DEFAULT now() NOT NULL,
    ADD COLUMN updated_at timestamp with time zone DEFAULT now() NOT NULL;

CREATE TRIGGER corporate_bodies_updated_at
    BEFORE UPDATE ON myenergy.corporate_bodies
    FOR EACH ROW EXECUTE FUNCTION myenergy.updated_at_now();

-- Add timestamps to customer_corporate_bodies
ALTER TABLE myenergy.customer_corporate_bodies
    ADD COLUMN created_at timestamp with time zone DEFAULT now() NOT NULL,
    ADD COLUMN updated_at timestamp with time zone DEFAULT now() NOT NULL;

CREATE TRIGGER customer_corporate_bodies_updated_at
    BEFORE UPDATE ON myenergy.customer_corporate_bodies
    FOR EACH ROW EXECUTE FUNCTION myenergy.updated_at_now();

-- Add timestamps to registered_proprietors
ALTER TABLE myenergy.registered_proprietors
    ADD COLUMN created_at timestamp with time zone DEFAULT now() NOT NULL,
    ADD COLUMN updated_at timestamp with time zone DEFAULT now() NOT NULL;

CREATE TRIGGER registered_proprietors_updated_at
    BEFORE UPDATE ON myenergy.registered_proprietors
    FOR EACH ROW EXECUTE FUNCTION myenergy.updated_at_now();

-- Enable RLS on registered_proprietors
ALTER TABLE myenergy.registered_proprietors ENABLE ROW LEVEL SECURITY;

-- Read policy - mirrors properties table pattern
DROP POLICY IF EXISTS "Customers can view their registered proprietors or all if cepro user"
  ON myenergy.registered_proprietors;
CREATE POLICY "Customers can view their registered proprietors or all if cepro user"
  ON myenergy.registered_proprietors
  FOR SELECT
  TO authenticated, public_backend, grafanareader
  USING (
    myenergy.is_backend_user()
    OR (customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email()))
    OR (EXISTS (
      SELECT 1 FROM myenergy.customers
      WHERE email = auth.session_email() AND cepro_user = true
    ))
  );

-- Enable RLS on corporate_bodies
ALTER TABLE myenergy.corporate_bodies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their corporate bodies or all if cepro user"
  ON myenergy.corporate_bodies;
CREATE POLICY "Customers can view their corporate bodies or all if cepro user"
  ON myenergy.corporate_bodies
  FOR SELECT
  TO authenticated, public_backend, grafanareader
  USING (
    myenergy.is_backend_user()
    OR EXISTS (
      SELECT 1
      FROM myenergy.customer_corporate_bodies ccb
      JOIN myenergy.customers c ON c.id = ccb.customer
      WHERE ccb.corporate_body = corporate_bodies.id
        AND c.email = auth.session_email()
    )
    OR EXISTS (
      SELECT 1 FROM myenergy.customers
      WHERE email = auth.session_email() AND cepro_user = true
    )
  );

-- Enable RLS on customer_corporate_bodies
ALTER TABLE myenergy.customer_corporate_bodies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their corporate body memberships or all if cepro user"
  ON myenergy.customer_corporate_bodies;
CREATE POLICY "Customers can view their corporate body memberships or all if cepro user"
  ON myenergy.customer_corporate_bodies
  FOR SELECT
  TO authenticated, public_backend, grafanareader
  USING (
    myenergy.is_backend_user()
    OR (customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email()))
    OR EXISTS (
      SELECT 1 FROM myenergy.customers
      WHERE email = auth.session_email() AND cepro_user = true
    )
  );

-- Replace add_property to create registered_proprietors record
CREATE OR REPLACE FUNCTION myenergy.add_property(plot_number text, esco_id uuid, solar_meter_serial text, supply_meter_serial text, description text, is_owner_occupied boolean, preonboard_only boolean) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    plot_name text := 'plot' || plot_number;
    esco_code text := (select code from myenergy.escos where id = esco_id); 
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
    INSERT INTO myenergy.customers (fullname, email, id) 
        VALUES (plot_name || ' Owner', plot_name || 'owner-' || esco_code || '@change.me', owner_id);

    -- Create occupier customer (if not owner occupied)
    IF is_owner_occupied = false THEN
        INSERT INTO myenergy.customers (fullname, email, id) 
            VALUES (plot_name || ' occupier', plot_name || 'occupier-' || esco_code || '@change.me', occupier_id);
    ELSE
        occupier_id := owner_id;
    END IF;

    -- Create property (owner column removed in 0020_shared_ownership_removal - use registered_proprietors instead)
    INSERT INTO myenergy.properties (plot, description, esco, id)
        VALUES (
            'Plot-' || plot_number,
            description,
            esco_id,
            property_id
        );

    -- Create registered_proprietors record for owner
    INSERT INTO myenergy.registered_proprietors (property, customer, tenure_type)
        VALUES (property_id, owner_id, 'joint_tenant');

    -- Handle solar installation if meter provided
    IF solar_meter_serial is not null THEN
        -- Create solar meter
        SELECT myenergy.add_meter(
            property_id, solar_meter_serial, false
        ) INTO solar_meter_id;

        -- Create solar account
        SELECT myenergy.add_account(
            'solar'::myenergy.account_type_enum,
            property_id,
            owner_id,
            occupier_id,
            null,  -- solar contract terms - owner will choose which contract terms
            preonboard_only  -- no_contract == true when preonboard
        ) INTO solar_account_id;
    END IF;

    -- Create supply meter
    SELECT myenergy.add_meter(
        property_id, supply_meter_serial, true
    ) INTO supply_meter_id;

    -- Get latest supply contract terms
    WITH latest_supply_terms_by_esco AS (
        select cte.terms, ct.version 
        from myenergy.contract_terms ct, myenergy.contract_terms_esco cte
        where cte.esco = esco_id
        and cte.terms = ct.id
        and ct."type" = 'supply'
        order by version desc
        limit 1
    ) SELECT terms FROM latest_supply_terms_by_esco INTO supply_contract_terms_id;

    -- Create supply account
    SELECT myenergy.add_account(
        'supply'::myenergy.account_type_enum,
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

CREATE OR REPLACE FUNCTION myenergy.summarise_property(p_property_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    prop_row myenergy.properties%ROWTYPE;
    owner_row myenergy.customers%ROWTYPE;
    supply_meter_row myenergy.meters%ROWTYPE;
    solar_meter_row myenergy.meters%ROWTYPE;
    supply_account_id uuid;
    solar_account_id uuid;
    rp_row myenergy.registered_proprietors%ROWTYPE;
BEGIN
    SELECT * INTO prop_row FROM myenergy.properties WHERE id = p_property_id;
    IF NOT FOUND THEN
        RAISE NOTICE 'Property not found: %', p_property_id;
        RETURN NULL;
    END IF;

    RAISE NOTICE E'\n=== Property Summary ===';
    RAISE NOTICE 'Plot: % | Description: % | ESCO: %', prop_row.plot, prop_row.description, prop_row.esco;

    SELECT * INTO rp_row FROM myenergy.registered_proprietors WHERE property = p_property_id LIMIT 1;
    IF FOUND THEN
        SELECT * INTO owner_row FROM myenergy.customers WHERE id = rp_row.customer;
        RAISE NOTICE 'Owner: % | %', owner_row.fullname, owner_row.email;
    END IF;

    SELECT * INTO supply_meter_row FROM myenergy.meters WHERE id = prop_row.supply_meter;
    IF FOUND THEN
        RAISE NOTICE 'Supply Meter: % | Serial: %', supply_meter_row.id, supply_meter_row.serial;
    END IF;

    IF prop_row.solar_meter IS NOT NULL THEN
        SELECT * INTO solar_meter_row FROM myenergy.meters WHERE id = prop_row.solar_meter;
        IF FOUND THEN
            RAISE NOTICE 'Solar Meter: % | Serial: %', solar_meter_row.id, solar_meter_row.serial;
        END IF;
    END IF;

    SELECT id INTO supply_account_id FROM myenergy.accounts WHERE property = p_property_id AND type = 'supply' LIMIT 1;
    IF supply_account_id IS NOT NULL THEN
        RAISE NOTICE 'Supply Account: %', supply_account_id;
    END IF;

    SELECT id INTO solar_account_id FROM myenergy.accounts WHERE property = p_property_id AND type = 'solar' LIMIT 1;
    IF solar_account_id IS NOT NULL THEN
        RAISE NOTICE 'Solar Account: %', solar_account_id;
    END IF;

    RAISE NOTICE '=======================';
    RETURN p_property_id::text;
END;
$$;

COMMIT;