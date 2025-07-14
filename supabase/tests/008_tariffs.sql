BEGIN;

SET search_path TO flows,extensions,myenergy,public;

SELECT plan(16);


SELECT is((SELECT current_role), 'postgres', 'intial role');

SELECT is((SELECT count(*)::int FROM benchmark_tariffs), 12, 'benchmark_tariffs count');
SELECT is((SELECT count(*)::int FROM microgrid_tariffs), 24, 'microgrid_tariffs count');
SELECT is((SELECT count(*)::int FROM customer_tariffs), 15, 'customer_tariffs count');
SELECT is((SELECT count(*)::int FROM monthly_costs), 9, 'monthly_costs count');

PREPARE get_microgrid_tariff AS
    SELECT computed_standing_charge, computed_unit_rate, emergency_credit, ecredit_button_threshold, debt_recovery_rate
    FROM   myenergy.microgrid_tariffs
    WHERE  esco = $1
    AND    period_start <= $2
    ORDER BY period_start DESC
    LIMIT 1;

SELECT results_eq(
    'EXECUTE get_microgrid_tariff(''363ff821-3a56-4b43-8227-8e53c45fbcdb'', ''2024-04-01'')', 
    $$ VALUES(0.503925, 0.175725, 15.0, 10.00, 0.25) $$,
    'microgrid tariffs for HMCE Apr-Jun 2024 computed correctly'
);
SELECT results_eq(
    'EXECUTE get_microgrid_tariff(''363ff821-3a56-4b43-8227-8e53c45fbcdb'', ''2024-07-01'')', 
    $$ VALUES(0.504075, 0.159975, 15.0, 10.00, 0.25) $$,
    'microgrid tariffs for HMCE Jul-Sep 2024 computed correctly'
);
SELECT results_eq(
    'EXECUTE get_microgrid_tariff(''363ff821-3a56-4b43-8227-8e53c45fbcdb'', ''2024-10-01'')', 
    $$ VALUES(0.5109, 0.175275, 15.0, 10.00, 0.25) $$,
    'microgrid tariffs for HMCE Oct-Dec 2024 computed correctly'
);
SELECT results_eq(
    'EXECUTE get_microgrid_tariff(''527eed5d-2f81-4abe-a7f4-6fff8ac72703'', ''2024-04-01'')', 
    $$ VALUES(0.503925, 0.175725, 15.0, 10.00, 0.25) $$,
    'microgrid tariffs for WLCE Apr-Jun 2024 computed correctly'
);
SELECT results_eq(
    'EXECUTE get_microgrid_tariff(''527eed5d-2f81-4abe-a7f4-6fff8ac72703'', ''2024-07-01'')', 
    $$ VALUES(0.504075, 0.159975, 15.0, 10.00, 0.25) $$,
    'microgrid tariffs for WLCE Jul-Sep 2024 computed correctly'
);
SELECT results_eq(
    'EXECUTE get_microgrid_tariff(''527eed5d-2f81-4abe-a7f4-6fff8ac72703'', ''2024-10-01'')', 
    $$ VALUES(0.5109, 0.175275, 15.0, 10.00, 0.25) $$,
    'microgrid tariffs for WLCE Oct-Dec 2024 computed correctly'
);

PREPARE get_customer_tariff AS
    SELECT computed_standing_charge, computed_unit_rate
    FROM   myenergy.customer_tariffs
    WHERE  customer = $1
    AND    period_start = $2;

SELECT results_eq(
    'EXECUTE get_customer_tariff(''a445daf9-66c3-4f46-b74d-2d82526c4a1c'', ''2024-04-01 00:00:00 +00'')', 
    $$ VALUES(0.6719, 0.2343) $$,
    'tariffs for WLCE customer ownocc12@wl.ce April 2024 no discount'
);
SELECT results_eq(
    'EXECUTE get_customer_tariff(''a445daf9-66c3-4f46-b74d-2d82526c4a1c'', ''2024-04-01 00:00:00 +00'')', 
    $$ VALUES(0.6719, 0.2343) $$,
    'tariffs for WLCE customer ownocc12@wl.ce May 2024 no discount (same range as April so same values)'
);

SELECT results_eq(
    'EXECUTE get_customer_tariff(''b4cf2b22-cc04-4c86-a910-c601cfdfc244'', ''2024-04-01 00:00:00 +00'')', 
    $$ VALUES(0.0, 0.0) $$,
    'tariffs for HMCE customer ownocc1@hm.ce Apr (initially 100% discount)'
);
SELECT results_eq(
    'EXECUTE get_customer_tariff(''b4cf2b22-cc04-4c86-a910-c601cfdfc244'', ''2024-07-01 00:00:00 +00'')', 
    $$ VALUES(0.6721, 0.2133) $$,
    'tariffs for HMCE customer ownocc1@hm.ce July (moves to 0 discount)'
);
SELECT results_eq(
    'EXECUTE get_customer_tariff(''c317324f-13e4-4b87-bc40-eae52928a415'', ''2024-10-01 00:00:00 +00'')', 
    $$ VALUES(0.51090, 0.17527) $$,
    'tariffs for HMCE cepro ownoccsea@hm.ce October (applies 25% discount and checks 6 decimal value truncated to 5)'
);


PREPARE get_monthly_cost AS
    SELECT heat, power, total, microgrid_total, benchmark_total
    FROM   myenergy.monthly_costs
    WHERE  customer_id = $1
    AND    month = $2;

-- TODO: get these working - the values are subtly different each time so some issue in the generation of the intervals:
--   - seed set for random() so should be deterministic
--   - checked timezones and time boundaries and they seem okay but dig deeper on this to be sure ...

-- SELECT results_eq(
--     'EXECUTE get_monthly_cost(''a445daf9-66c3-4f46-b74d-2d82526c4a1c'', ''2024-07-01'')', 
--     $$ VALUES(63.06431273440270037679900000000000000000000000000000000000000000,62.72799933654713980794975000000000000000000000000000000000000000,141.41863707094984018474875000000000000000000000000000000000000000,141.418637070949840184748750000000000000000000,188.5581827612664535796650) $$
-- );
-- SELECT results_eq(
--     'EXECUTE get_monthly_cost(''ef9007fa-4084-4775-b4f1-1c0710fc0511'', ''2024-07-01'')', 
--     $$ VALUES(0.00000000000000000000000000000000000000000000000000000000000000,0.00000000000000000000000000000000000000000000000000000000000000,0.00000000000000000000000000000000000000000000000000000000000000,138.173111430534052657073250000000000000000000,184.2308152407120702094310) $$
-- );

SELECT * FROM finish();
ROLLBACK;
