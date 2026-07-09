-- Deploy supabase:0027_generate_quarter_tariffs_hmce_only to pg
--
-- Scope the quarterly tariff generation triggered by benchmark_tariffs
-- inserts/updates to HMCE only.
--
-- background:
--   Inserting/updating myenergy.benchmark_tariffs fires
--   benchmark_tariffs_generate_tariffs_trigger, which calls
--   generate_new_quarter_tariffs(period_start). That function does two things:
--     Part 1 - inserts a new myenergy.microgrid_tariffs row for each ESCO
--     Part 2 - inserts a new myenergy.customer_tariffs row for each eligible
--              occupier customer
--   For Q3 2026 we have decided to freeze WLCE on its current (Q2 2026) rates
--   and only roll the new quarter's rates out to HMCE.
--
--   Filtering BOTH loops to HMCE is deliberate. If only the microgrid loop were
--   filtered, WLCE customers would still get new customer_tariffs rows with
--   new computed rates; the myenergy.meter_tariffs view (derived from
--   customer_tariffs) would then flag every WLCE meter as "incorrect" in
--   meters_with_incorrect_tariffs against a rate we are not pushing. Keeping
--   WLCE out of both loops leaves it entirely on its latest prior-quarter rows.
--
--   To re-enable WLCE in a future quarter, add 'wlce' to active_esco_codes
--   (or revert this change) and re-insert the benchmark for that quarter.

BEGIN;

CREATE OR REPLACE FUNCTION myenergy.generate_new_quarter_tariffs(month_in date) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  customer_rec RECORD;
  esco_rec RECORD;
  previous_rate INTEGER;
  previous_emergency_credit NUMERIC;
  previous_debt_recovery_rate NUMERIC;
  previous_ecredit_button_threshold NUMERIC;
  default_rate CONSTANT INTEGER := 25; -- Default rate if no previous rate found
  default_emergency_credit CONSTANT NUMERIC := 15; -- Default emergency credit amount
  default_debt_recovery_rate CONSTANT NUMERIC := 0.25; -- Default debt recovery rate
  default_ecredit_button_threshold CONSTANT NUMERIC := 10; -- Default emergency credit button threshold
  -- ESCOs that receive new quarterly tariff rows. WLCE is intentionally
  -- excluded (see migration 0027); add 'wlce' here to re-enable it.
  active_esco_codes CONSTANT text[] := ARRAY['hmce'];
  prev_quarter_start date;
  microgrid_updated_count INTEGER := 0;
  customer_updated_count INTEGER := 0;
BEGIN
  -- Calculate start of previous quarter (3 months before current month)
  prev_quarter_start := (month_in - INTERVAL '3 months')::date;

  -- Part 1: Update microgrid_tariffs for active escos only
  FOR esco_rec IN (
    SELECT DISTINCT mt.esco
    FROM myenergy.microgrid_tariffs mt
    JOIN myenergy.escos e ON e.id = mt.esco
    WHERE e.code = ANY(active_esco_codes)
  ) LOOP
    -- Try to find the previous quarter's microgrid tariff
    SELECT
      discount_rate_basis_points,
      emergency_credit,
      debt_recovery_rate,
      ecredit_button_threshold
    INTO
      previous_rate,
      previous_emergency_credit,
      previous_debt_recovery_rate,
      previous_ecredit_button_threshold
    FROM myenergy.microgrid_tariffs
    WHERE
      esco = esco_rec.esco
      AND period_start >= prev_quarter_start
      AND period_start < month_in
    ORDER BY period_start DESC
    LIMIT 1;

    -- If no previous tariff found, use default values
    IF previous_rate IS NULL THEN
      previous_rate := default_rate;
      previous_emergency_credit := default_emergency_credit;
      previous_debt_recovery_rate := default_debt_recovery_rate;
      previous_ecredit_button_threshold := default_ecredit_button_threshold;
    END IF;

    -- Insert new microgrid tariff record
    INSERT INTO myenergy.microgrid_tariffs(
      esco,
      period_start,
      discount_rate_basis_points,
      emergency_credit,
      debt_recovery_rate,
      ecredit_button_threshold
    )
    VALUES (
      esco_rec.esco,
      month_in,
      previous_rate,
      previous_emergency_credit,
      previous_debt_recovery_rate,
      previous_ecredit_button_threshold
    )
    ON CONFLICT (esco, period_start)
    DO UPDATE SET
      discount_rate_basis_points = EXCLUDED.discount_rate_basis_points,
      emergency_credit = EXCLUDED.emergency_credit,
      debt_recovery_rate = EXCLUDED.debt_recovery_rate,
      ecredit_button_threshold = EXCLUDED.ecredit_button_threshold;

    microgrid_updated_count := microgrid_updated_count + 1;
  END LOOP;


  -- Part 2: Update customer_tariffs for eligible customers in active escos only

  FOR customer_rec IN (
    SELECT c.id, c.email
    FROM myenergy.customers c
    JOIN myenergy.customer_accounts ca ON ca.customer = c.id
    JOIN myenergy.accounts a ON a.id = ca.account
    JOIN myenergy.properties p ON a.property = p.id
    JOIN myenergy.escos e ON p.esco = e.id
    WHERE c.status IN ('live', 'prelive', 'onboarding')
    AND ca.role = 'occupier'
    AND a.type = 'supply'
    AND e.code = ANY(active_esco_codes)
  ) LOOP
    -- Try to find the previous quarter's rate for this customer
    SELECT discount_rate_basis_points INTO previous_rate
    FROM myenergy.customer_tariffs ct
    WHERE
      ct.customer = customer_rec.id
      AND ct.period_start >= prev_quarter_start
      AND ct.period_start < month_in
    ORDER BY ct.period_start DESC
    LIMIT 1;

    -- If no previous rate found, use the default rate
    IF previous_rate IS NULL THEN
      previous_rate := default_rate;
    END IF;

    -- Insert new tariff record
    -- The computed_unit_rate and computed_standing_charge are auto-calculated by triggers
    INSERT INTO myenergy.customer_tariffs(customer, period_start, discount_rate_basis_points)
    VALUES (customer_rec.id, month_in, previous_rate)
    ON CONFLICT (customer, period_start)
    DO UPDATE SET discount_rate_basis_points = EXCLUDED.discount_rate_basis_points;

  RAISE NOTICE 'Updated tariffs for % ESCOs and % customers starting from %',
    microgrid_updated_count, customer_updated_count, month_in;
  END LOOP;
END;
$$;


ALTER FUNCTION myenergy.generate_new_quarter_tariffs(month_in date) OWNER TO :"adminrole";


COMMENT ON FUNCTION myenergy.generate_new_quarter_tariffs(month_in date) IS 'Generates both microgrid and customer tariffs for a new quarter.
Takes a date parameter representing the start of the new quarter.

Only ESCOs in the active_esco_codes array (currently HMCE only) receive new
rows. WLCE is intentionally frozen on its latest prior-quarter rates — see
migration 0027.

For microgrid tariffs:
- Updates the active ESCOs currently in the microgrid_tariffs table
- Carries over discount rates and emergency credit settings from the previous quarter
- Uses default values if no previous quarter data exists

For customer tariffs:
- Creates tariff records for customers with status "live" or "prelive", plus specified test accounts
- Carries over discount rates from the previous quarter, or uses default rate of 25 if no previous rate found
- Auto-computed columns are calculated by database triggers';

COMMIT;
