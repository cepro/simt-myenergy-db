BEGIN;
SELECT plan(5);

SET search_path TO flows,extensions,public;

SELECT is((SELECT current_role), 'postgres', 'intial role');

--
-- Check properties setup using check_property_setup() function
-- 

CREATE OR REPLACE FUNCTION property_has_supply_meter(property_id uuid)
RETURNS TEXT AS $$
    SELECT matches(
        (SELECT check_property_setup(property_id) LIMIT 1),
        '^Supply meter .* defined on property$',
        'property ' || property_id || ' has supply meter'
    );
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION property_has_solar_meter(property_id uuid)
RETURNS TEXT AS $$
    SELECT matches(
        (SELECT check_property_setup(property_id) OFFSET 1 LIMIT 1),
        '^Solar meter .* defined on property$',
        'property ' || property_id || ' has solar meter'
    );
$$ LANGUAGE sql;

SELECT property_has_supply_meter((select id from properties where description = '15 Water Lilies')::uuid);
SELECT property_has_solar_meter((select id from properties where description = '15 Water Lilies')::uuid);

SELECT property_has_supply_meter((select id from properties where description = '17 Hazelmead')::uuid);
SELECT property_has_solar_meter((select id from properties where description = '17 Hazelmead')::uuid);



SELECT * FROM finish();
ROLLBACK;
