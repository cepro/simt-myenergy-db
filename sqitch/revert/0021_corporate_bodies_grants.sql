-- Revert supabase:0021_corporate_bodies_grants from pg

BEGIN;

-- Drop policy and disable RLS on customer_corporate_bodies
DROP POLICY IF EXISTS "Customers can view their corporate body memberships or all if cepro user"
  ON myenergy.customer_corporate_bodies;
ALTER TABLE myenergy.customer_corporate_bodies DISABLE ROW LEVEL SECURITY;

-- Drop policy and disable RLS on corporate_bodies
DROP POLICY IF EXISTS "Customers can view their corporate bodies or all if cepro user"
  ON myenergy.corporate_bodies;
ALTER TABLE myenergy.corporate_bodies DISABLE ROW LEVEL SECURITY;

-- Drop policy and disable RLS on registered_proprietors
DROP POLICY IF EXISTS "Customers can view their registered proprietors or all if cepro user"
  ON myenergy.registered_proprietors;
ALTER TABLE myenergy.registered_proprietors DISABLE ROW LEVEL SECURITY;

-- Drop timestamps
DROP TRIGGER IF EXISTS registered_proprietors_updated_at ON myenergy.registered_proprietors;
ALTER TABLE myenergy.registered_proprietors DROP COLUMN IF EXISTS updated_at;
ALTER TABLE myenergy.registered_proprietors DROP COLUMN IF EXISTS created_at;

DROP TRIGGER IF EXISTS customer_corporate_bodies_updated_at ON myenergy.customer_corporate_bodies;
ALTER TABLE myenergy.customer_corporate_bodies DROP COLUMN IF EXISTS updated_at;
ALTER TABLE myenergy.customer_corporate_bodies DROP COLUMN IF EXISTS created_at;

DROP TRIGGER IF EXISTS corporate_bodies_updated_at ON myenergy.corporate_bodies;
ALTER TABLE myenergy.corporate_bodies DROP COLUMN IF EXISTS updated_at;
ALTER TABLE myenergy.corporate_bodies DROP COLUMN IF EXISTS created_at;

-- Restore original add_property (without registered_proprietors insert)
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

ALTER FUNCTION myenergy.add_property(plot_number text, esco_id uuid, solar_meter_serial text, supply_meter_serial text, description text, is_owner_occupied boolean, preonboard_only boolean) OWNER TO :"adminrole";

COMMIT;