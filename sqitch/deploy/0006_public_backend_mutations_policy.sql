-- Deploy supabase:0006_public_backend_mutations_policy to pg

BEGIN;

CREATE POLICY "Public backend can insert payments"
ON myenergy.payments
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can update payments"
ON myenergy.payments
FOR UPDATE
TO authenticated, public_backend
USING (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
)
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can insert topups"
ON myenergy.topups
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can update topups"
ON myenergy.topups
FOR UPDATE
TO authenticated, public_backend
USING (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
)
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can insert topups_payments"
ON myenergy.topups_payments
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can update topups_payments"
ON myenergy.topups_payments
FOR UPDATE
TO authenticated, public_backend
USING (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
)
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can insert topups_monthly_solar_credits"
ON myenergy.topups_monthly_solar_credits
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can update topups_monthly_solar_credits"
ON myenergy.topups_monthly_solar_credits
FOR UPDATE
TO authenticated, public_backend
USING (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
)
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can insert topups_gifts"
ON myenergy.topups_gifts
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

CREATE POLICY "Public backend can update topups_gifts"
ON myenergy.topups_gifts
FOR UPDATE
TO authenticated, public_backend
USING (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
)
WITH CHECK (
    (current_user = 'authenticated') AND (current_setting('request.jwt.claim.role', true) = 'public_backend')
);

COMMIT;
