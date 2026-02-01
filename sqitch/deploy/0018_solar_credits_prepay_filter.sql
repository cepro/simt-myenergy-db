-- Deploy supabase:0018_solar_credits_prepay_filter to pg
-- Remove prepay_enabled filter, add month-1 backfill, filter to live customers only

BEGIN;

CREATE OR REPLACE FUNCTION myenergy.monthly_solar_credits_unapplied(month_in text)
    RETURNS SETOF myenergy.monthly_solar_credits
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT msc.*
    FROM myenergy.monthly_solar_credits msc
    JOIN myenergy.properties p ON p.id = msc.property_id
    JOIN myenergy.meters m ON m.id = p.supply_meter
    JOIN myenergy.accounts a ON a.property = p.id AND a.type = 'supply'
    JOIN myenergy.customer_accounts ca ON ca.account = a.id AND ca.role = 'occupier'
    JOIN myenergy.customers c ON c.id = ca.customer
    WHERE msc.applied_at IS NULL
    AND msc.credit_pence > 0
    AND (msc."month" = month_in::date
         OR msc."month" = (month_in::date - INTERVAL '1 month')::date)
    AND msc."scheduled_at" < now()
    AND c.status = 'live';
    -- Removed: AND m.prepay_enabled IS NOT FALSE
    -- Added: month-1 backfill, customer status = 'live' filter
END;
$$;

COMMIT;
