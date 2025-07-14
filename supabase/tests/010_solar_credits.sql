BEGIN;

SET search_path TO extensions,myenergy,public;

SELECT plan(12);


-- Test days_in_month_all function
SELECT is(
    days_in_month_all('2025-02-01'::date),
    28,
    'February 2025 should have 28 days'
);

SELECT is(
    days_in_month_all('2024-02-01'::date),
    29,
    'February 2024 should have 29 days (leap year)'
);

SELECT is(
    days_in_month_all('2025-03-01'::date),
    31,
    'March 2025 should have 31 days'
);

-- Setup test data
INSERT INTO myenergy.escos (id, code, name, created_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'TEST1', 'Test ESCO 1', now())
ON CONFLICT (id) DO NOTHING;

-- Test solar_credit_tariffs credit_pence_per_day calculation
INSERT INTO myenergy.solar_credit_tariffs (esco, period_start, credit_pence_per_year)
VALUES 
    ('11111111-1111-1111-1111-111111111111', '2025-01-01', 3650),  -- 10 pence per day in non-leap year
    ('11111111-1111-1111-1111-111111111111', '2025-02-01', 3650),  -- Initial Feb rate (10 pence per day)
    ('11111111-1111-1111-1111-111111111111', '2024-01-01', 3660);  -- 10 pence per day in leap year

SELECT is(
    credit_pence_per_day,
    10.0,
    'Non-leap year daily rate should be exactly 10 pence'
)
FROM myenergy.solar_credit_tariffs
WHERE period_start = '2025-01-01'
AND esco = '11111111-1111-1111-1111-111111111111';

SELECT is(
    credit_pence_per_day,
    10.0,
    'Leap year daily rate should be exactly 10 pence'
)
FROM myenergy.solar_credit_tariffs
WHERE period_start = '2024-01-01'
AND esco = '11111111-1111-1111-1111-111111111111';

-- Setup more test data for monthly credits
INSERT INTO myenergy.customers (id, email, fullname)
VALUES ('22222222-2222-2222-2222-222222222222', 'test@example.com', 'Test User')
ON CONFLICT (id) DO NOTHING;

INSERT INTO myenergy.meters (id, serial)
VALUES ('33333333-3333-3333-3333-333333333333', 'TEST-METER-001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO myenergy.properties (
    id, plot, owner, esco, solar_meter
) VALUES (
    '44444444-4444-4444-4444-444444444444',
    'TEST-PLOT',
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111',
    '33333333-3333-3333-3333-333333333333'
) ON CONFLICT (id) DO UPDATE 
SET solar_meter = '33333333-3333-3333-3333-333333333333',
    esco = '11111111-1111-1111-1111-111111111111';

INSERT INTO myenergy.solar_installation (property, mcs, declared_net_capacity)
VALUES ('44444444-4444-4444-4444-444444444444', 'TEST-MCS-001', 3.5)
ON CONFLICT (property) DO UPDATE 
SET declared_net_capacity = 3.5;

-- Test monthly solar credits computation
INSERT INTO myenergy.monthly_solar_credits (property_id, month)
VALUES ('44444444-4444-4444-4444-444444444444', '2025-02-01');

-- February 2025 credit should be:
-- 3.5 kW * 28 days * 10 pence = 980 pence
SELECT is(
    credit_pence,
    980,
    'February 2025 credit should be 980 pence (3.5kW * 28 days * 10p)'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2025-02-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

-- Test January 2025 (31 days)
INSERT INTO myenergy.monthly_solar_credits (property_id, month)
VALUES ('44444444-4444-4444-4444-444444444444', '2025-01-01');

SELECT is(
    credit_pence,
    1085,
    'January 2025 credit should be 1085 pence (3.5kW * 31 days * 10p)'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2025-01-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

-- Test credit calculation with zero capacity
UPDATE myenergy.solar_installation
SET declared_net_capacity = 0
WHERE property = '44444444-4444-4444-4444-444444444444';

INSERT INTO myenergy.monthly_solar_credits (property_id, month)
VALUES ('44444444-4444-4444-4444-444444444444', '2025-03-01');

SELECT is(
    credit_pence,
    0,
    'Credit should be 0 when capacity is 0'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2025-03-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

-- Test credit calculation with null capacity
UPDATE myenergy.solar_installation
SET declared_net_capacity = null
WHERE property = '44444444-4444-4444-4444-444444444444';

INSERT INTO myenergy.monthly_solar_credits (property_id, month)
VALUES ('44444444-4444-4444-4444-444444444444', '2025-04-01');

SELECT is(
    credit_pence,
    0,
    'Credit should be 0 when capacity is null'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2025-04-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

-- Test non-existent tariff period
INSERT INTO myenergy.monthly_solar_credits (property_id, month)
VALUES ('44444444-4444-4444-4444-444444444444', '2023-01-01');

SELECT is(
    credit_pence,
    0,
    'Credit should be 0 when no applicable tariff exists'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2023-01-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

-- Test credit calculation updates when tariff changes
UPDATE myenergy.solar_installation
SET declared_net_capacity = 3.5
WHERE property = '44444444-4444-4444-4444-444444444444';

-- Update the existing tariff to new amount
UPDATE myenergy.solar_credit_tariffs 
SET credit_pence_per_year = 7300  -- 20 pence per day
WHERE esco = '11111111-1111-1111-1111-111111111111'
AND period_start = '2025-02-01';

-- Delete and reinsert the monthly credit to force recalculation
DELETE FROM myenergy.monthly_solar_credits 
WHERE property_id = '44444444-4444-4444-4444-444444444444'
AND month = '2025-02-01';

INSERT INTO myenergy.monthly_solar_credits (property_id, month)
VALUES ('44444444-4444-4444-4444-444444444444', '2025-02-01');

SELECT is(
    credit_pence,
    1960,
    'February 2025 credit should update to 1960 pence (3.5kW * 28 days * 20p) after tariff change'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2025-02-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

-- Additional test to verify consistent calculation
SELECT is(
    credit_pence,
    1960,
    'Verify February 2025 credit remains 1960 pence'
)
FROM myenergy.monthly_solar_credits
WHERE month = '2025-02-01'
AND property_id = '44444444-4444-4444-4444-444444444444';

SELECT * FROM finish();
ROLLBACK;