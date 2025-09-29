-- Deploy supabase:fix_register_id_null_on_trigger to pg

BEGIN;

CREATE POLICY "Customers and backend can update gifts"
ON myenergy.gifts
FOR UPDATE
TO authenticated, public_backend
USING (
    myenergy.is_backend_user() OR customer_id = myenergy.customer()
)
WITH CHECK (
    myenergy.is_backend_user() OR customer_id = myenergy.customer()
);

-- Fix register_import_a_insert function
CREATE OR REPLACE FUNCTION flows.register_import_a_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    _register_id uuid;
BEGIN
    -- Skip if import_a is NULL
    IF new.import_a IS NULL THEN
        RETURN new;
    END IF;

    SELECT mr.register_id INTO _register_id
    FROM flows.meter_registers mr
    WHERE mr.meter_id = new.id AND mr.element = 'A';

    IF _register_id IS NULL THEN
        RAISE WARNING 'No register found for meter_id % element A - import_a 
insert skipped', new.id;
        RETURN new;
    END IF;

    -- Double-check register_id is not NULL before insert
    IF _register_id IS NOT NULL THEN
        INSERT INTO "flows"."register_import"(register_id, read, "timestamp")
        VALUES (_register_id, new.import_a, new.updated_at)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN new;
END;
$function$;

-- Fix register_import_b_insert function  
CREATE OR REPLACE FUNCTION flows.register_import_b_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    _register_id uuid;
BEGIN
    -- Skip if import_b is NULL
    IF new.import_b IS NULL THEN
        RETURN new;
    END IF;

    SELECT mr.register_id INTO _register_id
    FROM flows.meter_registers mr
    WHERE mr.meter_id = new.id AND mr.element = 'B';

    IF _register_id IS NULL THEN
        RAISE WARNING 'No register found for meter_id % element B - import_b 
insert skipped', new.id;
        RETURN new;
    END IF;

    -- Double-check register_id is not NULL before insert
    IF _register_id IS NOT NULL THEN
        INSERT INTO "flows"."register_import"(register_id, read, "timestamp")
        VALUES (_register_id, new.import_b, new.updated_at)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN new;
END;
$function$;

COMMIT;
