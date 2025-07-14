BEGIN;

SET search_path TO myenergy,extensions,flows,public;

SELECT plan(13);

-- 
-- tableau
--  

-- grant extensions for pgtap functions is, throws_ok, etc.
GRANT USAGE ON SCHEMA extensions TO tableau;

GRANT tableau TO postgres;
SET ROLE tableau;

SELECT ok((SELECT TRUE FROM flows.meter_registry WHERE id is not null limit 1), 'select on meter_registry');
SELECT ok((SELECT TRUE FROM flows.meter_shadows WHERE id is not null limit 1), 'select on meter_shadows');
SELECT ok((SELECT TRUE FROM flows.meter_csq WHERE meter_id is not null limit 1), 'select on meter_csq');
SELECT ok((SELECT TRUE FROM flows.meter_health_history WHERE meter_id is not null limit 1), 'select on meter_health_history');
SELECT is((SELECT count(*)::int FROM flows.meter_voltage), 0, 'select on meter_voltage');
SELECT is((SELECT count(*)::int FROM flows.meter_3p_voltage), 0, 'select on meter_3p_voltage');
-- SELECT is((SELECT count(*)::int FROM flux.mg_bess_readings), 0, 'select on mg_bess_readings');
-- SELECT is((SELECT count(*)::int FROM flux.mg_meter_readings), 0, 'select on mg_meter_readings');
-- SELECT is((SELECT count(*)::int FROM flux.market_data), 0, 'select on market_data');

SELECT throws_ok(
    $$ select * from myenergy.customers $$,
    'permission denied for table customers'
);

-- 
-- public_backend
--  

-- grant extensions for pgtap functions is, throws_ok, etc.
SET ROLE postgres;
GRANT USAGE ON SCHEMA extensions TO public_backend;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'public_backend', false);
SET search_path TO extensions,myenergy;

SELECT ok((SELECT TRUE FROM myenergy.customers WHERE id is not null limit 1), 'select on customers');
SELECT ok((SELECT TRUE FROM myenergy.customer_invites WHERE invite_token is not null limit 1), 'select on customer_invites');
SELECT ok((SELECT TRUE FROM myenergy.contracts WHERE id is not null limit 1), 'select on contracts');
SELECT ok((SELECT TRUE FROM myenergy.contract_terms WHERE id is not null limit 1), 'select on contract_terms');
SELECT ok((SELECT TRUE FROM myenergy.escos WHERE id is not null limit 1), 'select on escos');
SELECT ok((SELECT TRUE FROM myenergy.properties WHERE id is not null limit 1), 'select on properties');

SELECT * FROM finish();
ROLLBACK;
