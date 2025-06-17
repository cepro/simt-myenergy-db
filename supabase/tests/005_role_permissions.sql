BEGIN;
SELECT plan(17);

SET search_path TO extensions,flows,public;

-- 
-- tableau
--  

-- grant extensions for pgtap functions is, throws_ok, etc.
GRANT USAGE ON SCHEMA extensions TO tableau;

GRANT tableau TO postgres;
SET ROLE tableau;

SELECT ok((SELECT TRUE FROM meter_registry WHERE id is not null limit 1), 'select on meter_registry');
SELECT ok((SELECT TRUE FROM meter_shadows WHERE id is not null limit 1), 'select on meter_shadows');
SELECT ok((SELECT TRUE FROM meter_csq WHERE meter_id is not null limit 1), 'select on meter_csq');
SELECT ok((SELECT TRUE FROM meter_health_history WHERE meter_id is not null limit 1), 'select on meter_health_history');
SELECT is((SELECT count(*)::int FROM meter_voltage), 0, 'select on meter_voltage');
SELECT is((SELECT count(*)::int FROM meter_3p_voltage), 0, 'select on meter_3p_voltage');
SELECT is((SELECT count(*)::int FROM mg_bess_readings), 0, 'select on mg_bess_readings');
SELECT is((SELECT count(*)::int FROM mg_meter_readings), 0, 'select on mg_meter_readings');
SELECT is((SELECT count(*)::int FROM market_data), 0, 'select on market_data');

SELECT throws_ok(
    $$ select * from public.sites $$,
    'permission denied for table sites'
);
SELECT throws_ok(
    $$ select * from public.customers $$,
    'permission denied for table customers'
);

-- 
-- public_backend
--  

-- grant extensions for pgtap functions is, throws_ok, etc.
SET ROLE postgres;
GRANT USAGE ON SCHEMA extensions TO public_backend;

GRANT public_backend TO postgres;
SET ROLE public_backend;

SET search_path TO extensions,public;

SELECT ok((SELECT TRUE FROM customers WHERE id is not null limit 1), 'select on customers');
SELECT ok((SELECT TRUE FROM customer_invites WHERE invite_token is not null limit 1), 'select on customer_invites');
-- TODO: Currently no contracts but they will be restored soon, uncomment this at that time:
-- SELECT ok((SELECT TRUE FROM contracts WHERE id is not null limit 1), 'select on contracts');
SELECT ok((SELECT TRUE FROM contract_terms WHERE id is not null limit 1), 'select on contract_terms');
SELECT ok((SELECT TRUE FROM sites WHERE id is not null limit 1), 'select on sites');
SELECT ok((SELECT TRUE FROM escos WHERE id is not null limit 1), 'select on escos');
SELECT ok((SELECT TRUE FROM properties WHERE id is not null limit 1), 'select on properties');

SELECT * FROM finish();
ROLLBACK;
