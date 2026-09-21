-- Deploy supabase:0030_solar_credits_exclude_expired_contracts to pg
-- WLCE solar contracts are being ended (end_date set on myenergy.contracts).
-- Stop the apply flow from paying out solar credits for properties whose
-- solar contract has already ended. NULL end_date = no expiry = still payable.
-- Also locks the RPC down to `anon` (the PostgREST role the Java handler
-- executes as); PUBLIC previously had EXECUTE.

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
    AND c.status = 'live'
    AND NOT EXISTS (
        SELECT 1
        FROM myenergy.accounts sa
        JOIN myenergy.contracts sc ON sc.id = sa.current_contract
        WHERE sa.property = p.id
          AND sa.type = 'solar'
          AND sc.type = 'solar'
          AND sc.end_date IS NOT NULL
          AND sc.end_date < CURRENT_DATE
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION myenergy.monthly_solar_credits_unapplied(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION myenergy.monthly_solar_credits_unapplied(text) TO anon;

COMMIT;
