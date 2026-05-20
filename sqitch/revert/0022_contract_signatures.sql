-- Revert supabase:0022_contract_signatures from pg

BEGIN;

-- Drop views first (they depend on contracts columns)
DROP VIEW IF EXISTS myenergy.account_contract_meter_row_per_property;
DROP VIEW IF EXISTS myenergy.account_contract_meter_flattened;
DROP VIEW IF EXISTS myenergy.property_supply_view;
DROP VIEW IF EXISTS myenergy.property_solar_view;

-- Drop the new trigger and function
DROP TRIGGER IF EXISTS contract_signatures_update_signed ON myenergy.contract_signatures;
DROP FUNCTION IF EXISTS myenergy.update_contract_signed_status();

-- Drop the new RLS policies and disable RLS on contract_signatures
ALTER TABLE myenergy.contract_signatures DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Customers can view their contract signatures" ON myenergy.contract_signatures;
DROP POLICY IF EXISTS "Customers can insert their own contract signatures" ON myenergy.contract_signatures;
DROP POLICY IF EXISTS "Customers can delete their own contract signatures" ON myenergy.contract_signatures;

-- Add signed_date column back first (before we can migrate data to it)
ALTER TABLE myenergy.contracts ADD COLUMN signed_date date;

-- Migrate data back from contract_signatures to signed_date
UPDATE myenergy.contracts c
SET signed_date = (
    SELECT MIN(cs.signed_date)
    FROM myenergy.contract_signatures cs
    WHERE cs.contract = c.id
)
WHERE EXISTS (
    SELECT 1 FROM myenergy.contract_signatures cs WHERE cs.contract = c.id
);

-- Drop the new columns
ALTER TABLE myenergy.contracts DROP COLUMN IF EXISTS signatures_required;
ALTER TABLE myenergy.contracts DROP COLUMN IF EXISTS signed;

-- Drop the contract_signatures table
DROP TABLE IF EXISTS myenergy.contract_signatures;

-- Recreate the old trigger function
CREATE FUNCTION myenergy.contracts_signed_update_customer_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
     customer_id uuid;
     customer_row myenergy.customers;
     new_status myenergy.customer_status_enum;
BEGIN
    IF OLD.signed_date is null AND NEW.signed_date IS NOT NULL THEN
        SELECT "customer" FROM "myenergy"."customer_accounts" WHERE account IN (
            SELECT id FROM myenergy.accounts WHERE current_contract = NEW.id
        )
        INTO customer_id;
        SELECT * FROM "myenergy"."customers" WHERE id = customer_id INTO customer_row;
        SELECT myenergy.customer_status(customer_row) INTO new_status;
        UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION myenergy.contracts_signed_update_customer_status() OWNER TO :"adminrole";

-- Recreate the old trigger
CREATE TRIGGER contracts_signed_date_update_trigger
    AFTER UPDATE OF signed_date ON myenergy.contracts
    FOR EACH ROW EXECUTE FUNCTION myenergy.contracts_signed_update_customer_status();

-- Recreate original property_solar_view with signed_date
CREATE VIEW myenergy.property_solar_view AS
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
   FROM ((((myenergy.property_base_view p
     LEFT JOIN myenergy.accounts a ON (((p.property_id = a.property) AND (a.type = 'solar'::myenergy.account_type_enum))))
     LEFT JOIN myenergy.contracts co ON ((a.current_contract = co.id)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (myenergy.customer_accounts ca
             JOIN myenergy.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'owner'::myenergy.account_role_type_enum)) so ON ((a.id = so.account)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (myenergy.customer_accounts ca
             JOIN myenergy.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'occupier'::myenergy.account_role_type_enum)) soc ON ((a.id = soc.account)));

ALTER VIEW myenergy.property_solar_view OWNER TO :"adminrole";

-- Recreate original property_supply_view with signed_date
CREATE VIEW myenergy.property_supply_view AS
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
   FROM (((((myenergy.property_base_view p
     LEFT JOIN myenergy.accounts a ON (((p.property_id = a.property) AND (a.type = 'supply'::myenergy.account_type_enum))))
     LEFT JOIN myenergy.contracts co ON ((a.current_contract = co.id)))
     LEFT JOIN myenergy.meters m ON ((p.supply_meter = m.id)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (myenergy.customer_accounts ca
             JOIN myenergy.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'owner'::myenergy.account_role_type_enum)) so ON ((a.id = so.account)))
     LEFT JOIN ( SELECT ca.account,
            c.fullname,
            c.email,
            c.status,
            c.updated_at
           FROM (myenergy.customer_accounts ca
             JOIN myenergy.customers c ON ((ca.customer = c.id)))
          WHERE (ca.role = 'occupier'::myenergy.account_role_type_enum)) soc ON ((a.id = soc.account)));

ALTER VIEW myenergy.property_supply_view OWNER TO :"adminrole";

-- Recreate original account_contract_meter_flattened with signed_date
CREATE VIEW myenergy.account_contract_meter_flattened AS
 SELECT myenergy.generate_v4_uuid_from_hash(concat(e.code, p.plot, c.email, a.id)) AS id,
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
   FROM myenergy.customers c,
    myenergy.customer_accounts ca,
    myenergy.properties p,
    myenergy.escos e,
    myenergy.meters m,
    (myenergy.contracts co
     RIGHT JOIN myenergy.accounts a ON ((a.current_contract = co.id)))
  WHERE ((c.id = ca.customer) AND (ca.account = a.id) AND (a.property = p.id) AND (p.esco = e.id) AND (p.supply_meter = m.id));

ALTER VIEW myenergy.account_contract_meter_flattened OWNER TO :"adminrole";

-- Recreate original account_contract_meter_row_per_property
CREATE VIEW myenergy.account_contract_meter_row_per_property AS
 SELECT myenergy.generate_v4_uuid_from_hash(concat(b.property_id, p.supply_account_id)) AS id,
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
   FROM ((myenergy.property_base_view b
     LEFT JOIN myenergy.property_solar_view s ON ((b.property_id = s.property_id)))
     LEFT JOIN myenergy.property_supply_view p ON ((b.property_id = p.property_id)));

ALTER VIEW myenergy.account_contract_meter_row_per_property OWNER TO :"adminrole";

COMMIT;