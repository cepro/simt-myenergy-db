-- Deploy supabase:0019_shared_ownership to pg
-- Add corporate_bodies and registered_proprietors tables for shared ownership

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

-- Drop deprecated properties.owner column
-- ALTER TABLE myenergy.properties DROP COLUMN IF EXISTS owner;
COMMENT ON COLUMN myenergy.properties.owner IS 'deprecated: to be removed in future';

COMMIT;
