-- Revert supabase:0018_solar_credits_prepay_filter from pg
-- Restore original function with prepay filter and single month

BEGIN;

CREATE OR REPLACE FUNCTION myenergy.monthly_solar_credits_unapplied(month_in text)
    RETURNS SETOF myenergy.monthly_solar_credits
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT msc.*
    FROM myenergy.monthly_solar_credits msc, myenergy.properties p, myenergy.meters m
    WHERE msc.applied_at IS NULL
    AND msc.credit_pence > 0
    AND msc."month" = month_in::date
    AND msc."scheduled_at" < now()
    AND msc.property_id = p.id
    AND p.supply_meter = m.id
    AND m.prepay_enabled IS NOT FALSE;
END;
$$;

COMMIT;
