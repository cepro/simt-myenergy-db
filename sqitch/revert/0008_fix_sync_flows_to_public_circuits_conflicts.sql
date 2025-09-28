-- Revert myenergy:0008_fix_sync_flows_to_public_circuits_conflicts from pg

BEGIN;

CREATE OR REPLACE FUNCTION myenergy.sync_flows_to_public_circuits()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    latest_record_date timestamptz;
BEGIN
    SELECT COALESCE(MAX(created_at), '2020-01-01'::DATE)
    FROM myenergy.circuits
    INTO latest_record_date;

    INSERT INTO myenergy.circuits (id, type, name, created_at)
    SELECT
        id,
        type::text::myenergy.circuit_type_enum,
        name,
        created_at
    FROM flows.circuits
    WHERE created_at > latest_record_date;

    SELECT COALESCE(MAX(created_at), '2020-01-01'::DATE)
    FROM myenergy.circuit_meter
    INTO latest_record_date;

    INSERT INTO myenergy.circuit_meter
        SELECT DISTINCT cr.circuit as circuit_id, pm.id as meter_id
        FROM flows.circuit_register cr
        JOIN flows.meter_registers mr ON cr.register = mr.register_id
        JOIN flows.meter_registry reg ON mr.meter_id = reg.id
        JOIN myenergy.meters pm ON reg.serial = pm.serial
        WHERE cr.created_at > latest_record_date;
END;
$function$;

COMMIT;
