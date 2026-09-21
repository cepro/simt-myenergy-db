-- Revert supabase:0030_solar_credits_exclude_expired_contracts from pg
-- Restore the exact 0018 body and the pre-0030 privileges (EXECUTE to PUBLIC).

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
END;
$$;

REVOKE EXECUTE ON FUNCTION myenergy.monthly_solar_credits_unapplied(text) FROM anon;
GRANT EXECUTE ON FUNCTION myenergy.monthly_solar_credits_unapplied(text) TO PUBLIC;

COMMIT;
