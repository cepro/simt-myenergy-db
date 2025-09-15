BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO myenergy, flows, public, extensions;

SELECT extensions.plan(16);


SELECT is((SELECT current_role), 'tsdbadmin', 'intial role');

--
-- Check initial state of the data as the following tests depend on it
-- 

SELECT is((SELECT count(*)::int FROM meter_registry), 44, 'initial meter_registry count');
SELECT is((SELECT count(*)::int FROM meter_shadows), 44, 'initial meter_shadows count');
SELECT is((SELECT count(*)::int FROM meter_csq), 41, 'initially 39 records');
SELECT is((SELECT count(*)::int FROM meter_health_history), 41, 'initial health_history count');

--
-- Check triggers that create meter_health_history records
--

UPDATE meter_shadows SET health = 'unhealthy' WHERE id = '04cefec3-75c7-40a0-9689-9f5005f0e592';
SELECT is((SELECT count(*)::int FROM meter_health_history), 42, '1 new record');
SELECT is((SELECT count(*)::int FROM meter_csq), 41, 'unchanged as csq did not change');

PREPARE health_in_history AS SELECT health FROM meter_health_history WHERE meter_id = '04cefec3-75c7-40a0-9689-9f5005f0e592' order by timestamp desc limit 1;
SELECT results_eq(
    'health_in_history', 
    $$ VALUES('unhealthy'::health_check_status) $$,
    'health status in new record is correct'
);


--
-- Check triggers that create meter_csq records
--

-- different csq - should create new meter_csq record with new value
UPDATE meter_shadows SET csq = 22 WHERE id = '04cefec3-75c7-40a0-9689-9f5005f0e592';
SELECT is((SELECT count(*)::int FROM meter_csq), 42, '1 new record');

PREPARE csq_updated AS SELECT csq FROM meter_csq WHERE meter_id = '04cefec3-75c7-40a0-9689-9f5005f0e592' order by timestamp desc limit 1;
SELECT results_eq(
    'csq_updated', 
    $$ VALUES(22) $$,
    'csq in new record is correct'
);

-- same csq - also creates a new record in meter_csq so as not to leave gaps
UPDATE meter_shadows SET csq = 22 WHERE id = '04cefec3-75c7-40a0-9689-9f5005f0e592';
SELECT is((SELECT count(*)::int FROM meter_csq), 43, '1 new record');

SELECT results_eq(
    'csq_updated', 
    $$ VALUES(22) $$,
    'latest csq unchanged'
);

-- null csq - inserts null indicating no connectivity at all - unable to get csq
UPDATE meter_shadows SET csq = null WHERE id = '04cefec3-75c7-40a0-9689-9f5005f0e592';
SELECT is((SELECT count(*)::int FROM meter_csq), 44, '1 new record for the null');

SELECT is(
     (SELECT csq FROM meter_csq WHERE meter_id = '04cefec3-75c7-40a0-9689-9f5005f0e592' order by timestamp desc limit 1),
    null,
    'latest csq is null'
);

--
-- Check auth is restricted to the flows role
-- 

-- anon
set role anon;
SELECT set_config('request.jwt.claim.email', null, true);
SELECT throws_ok(
    $$ select * from flows.meter_shadows $$,
    'permission denied for schema flows'
);

-- ordinary user in auth.users
set role authenticated;
set request.jwt.claim.email = 'own11_13@wl.ce';
SELECT throws_ok(
    $$ select * from flows.meter_shadows $$,
    'permission denied for schema flows'
);

SELECT set_config('request.jwt.claim.email', null, true);

-- flows role
set role tsdbadmin;
GRANT flows to tsdbadmin;
set role flows;

select * from flows.meter_shadows;

set role tsdbadmin;

SELECT * FROM finish();
ROLLBACK;
