-- Deploy supabase:0022_contract_signatures to pg
-- Add contract_signatures table, drop signed_date, add signed bool with signatures_required

BEGIN;

-- Create contract_signatures table
CREATE TABLE myenergy.contract_signatures (
    contract uuid NOT NULL REFERENCES myenergy.contracts(id) ON DELETE CASCADE,
    customer uuid NOT NULL REFERENCES myenergy.customers(id) ON DELETE CASCADE,
    signed_date date DEFAULT current_date NOT NULL,
    PRIMARY KEY (contract, customer)
);

ALTER TABLE myenergy.contract_signatures OWNER TO :"adminrole";

COMMENT ON TABLE myenergy.contract_signatures IS 'Joins contracts with signatures. Tracks who signed a contract and when.';

-- Add signatures_required and signed columns to contracts
ALTER TABLE myenergy.contracts
    ADD COLUMN signatures_required integer DEFAULT 1 NOT NULL,
    ADD COLUMN signed boolean DEFAULT false NOT NULL;

COMMENT ON COLUMN myenergy.contracts.signatures_required IS 'Number of signatures required for this contract to be considered fully signed.';
COMMENT ON COLUMN myenergy.contracts.signed IS 'True once all required signatures have been collected in contract_signatures.';

-- Update views that depend on signed_date before dropping the column
DROP VIEW IF EXISTS myenergy.account_contract_meter_row_per_property;
DROP VIEW IF EXISTS myenergy.account_contract_meter_flattened;
DROP VIEW IF EXISTS myenergy.property_supply_view;
DROP VIEW IF EXISTS myenergy.property_solar_view;

-- Recreate property_solar_view without signed_date
CREATE VIEW myenergy.property_solar_view AS
 SELECT p.property_id,
    a.id AS solar_account_id,
    a.account_number AS solar_account_number,
    a.status AS solar_account_status,
    co.id AS solar_contract_id,
    co.type AS solar_contract_type,
    co.terms AS solar_contract_terms,
    co.signed AS solar_signed,
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

-- Recreate property_supply_view without signed_date
CREATE VIEW myenergy.property_supply_view AS
 SELECT p.property_id,
    a.id AS supply_account_id,
    a.account_number AS supply_account_number,
    a.status AS supply_account_status,
    co.id AS supply_contract_id,
    co.type AS supply_contract_type,
    co.terms AS supply_contract_terms,
    co.signed AS supply_signed,
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

-- Recreate account_contract_meter_flattened without signed_date
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
    co.signed AS contract_signed,
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

-- Recreate account_contract_meter_row_per_property with updated view structure
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
    s.solar_signed,
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
    p.supply_signed,
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

-- Drop the old trigger and function first (they depend on signed_date column)
DROP TRIGGER IF EXISTS contracts_signed_date_update_trigger ON myenergy.contracts;
DROP FUNCTION IF EXISTS myenergy.contracts_signed_update_customer_status();

-- Migrate existing signed_date data to contract_signatures
INSERT INTO myenergy.contract_signatures (contract, customer, signed_date)
SELECT c.id, ca.customer, c.signed_date
FROM myenergy.contracts c
JOIN myenergy.customer_accounts ca ON ca.account = ANY(
    SELECT id FROM myenergy.accounts WHERE current_contract = c.id
)
WHERE c.signed_date IS NOT NULL;

-- Drop the old signed_date column
ALTER TABLE myenergy.contracts DROP COLUMN signed_date;

-- Now create the new signature counting logic
CREATE OR REPLACE FUNCTION myenergy.update_contract_signed_status()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    sig_count integer;
    req_count integer;
    customer_id uuid;
    customer_row myenergy.customers;
    new_status myenergy.customer_status_enum;
BEGIN
    SELECT COUNT(*) INTO sig_count
    FROM myenergy.contract_signatures
    WHERE contract = COALESCE(NEW.contract, OLD.contract);

    SELECT signatures_required INTO req_count
    FROM myenergy.contracts
    WHERE id = COALESCE(NEW.contract, OLD.contract);

    UPDATE myenergy.contracts
    SET signed = (sig_count >= req_count)
    WHERE id = COALESCE(NEW.contract, OLD.contract);

    IF sig_count >= req_count THEN
        SELECT customer INTO customer_id
        FROM myenergy.customer_accounts
        WHERE account = ANY(
            SELECT id FROM myenergy.accounts WHERE current_contract = COALESCE(NEW.contract, OLD.contract)
        )
        LIMIT 1;

        IF customer_id IS NOT NULL THEN
            SELECT * INTO customer_row FROM myenergy.customers WHERE id = customer_id;
            SELECT myenergy.customer_status(customer_row) INTO new_status;
            UPDATE myenergy.customers SET status = new_status WHERE id = customer_id;
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

ALTER FUNCTION myenergy.update_contract_signed_status() OWNER TO :"adminrole";

CREATE TRIGGER contract_signatures_update_signed
    AFTER INSERT OR UPDATE OR DELETE ON myenergy.contract_signatures
    FOR EACH ROW EXECUTE FUNCTION myenergy.update_contract_signed_status();

ALTER TABLE myenergy.contract_signatures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their contract signatures" ON myenergy.contract_signatures;
CREATE POLICY "Customers can view their contract signatures"
    ON myenergy.contract_signatures
    FOR SELECT
    TO authenticated, public_backend, grafanareader
    USING (
        myenergy.is_backend_user()
        OR customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email())
        OR EXISTS (
            SELECT 1 FROM myenergy.customers
            WHERE email = auth.session_email() AND cepro_user = true
        )
    );

DROP POLICY IF EXISTS "Customers can insert their own contract signatures" ON myenergy.contract_signatures;
CREATE POLICY "Customers can insert their own contract signatures"
    ON myenergy.contract_signatures
    FOR INSERT
    TO authenticated, public_backend
    WITH CHECK (
        customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email())
        OR myenergy.is_backend_user()
    );

DROP POLICY IF EXISTS "Customers can delete their own contract signatures" ON myenergy.contract_signatures;
CREATE POLICY "Customers can delete their own contract signatures"
    ON myenergy.contract_signatures
    FOR DELETE
    TO authenticated, public_backend
    USING (
        customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email())
        OR myenergy.is_backend_user()
    );

COMMIT;