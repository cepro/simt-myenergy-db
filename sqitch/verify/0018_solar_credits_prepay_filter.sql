-- Verify supabase:0018_solar_credits_prepay_filter on pg

BEGIN;

-- Verify function exists
SELECT 1 FROM pg_proc WHERE proname = 'monthly_solar_credits_unapplied';

ROLLBACK;
