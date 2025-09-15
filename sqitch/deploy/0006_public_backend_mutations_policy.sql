-- Deploy supabase:0006_public_backend_mutations_policy to pg

BEGIN;

DROP POLICY "Customers and backend can update topups" ON myenergy.topups;

CREATE POLICY "Customers and backend can insert topups"
ON myenergy.topups
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        meter IN (
            SELECT meters.id
            FROM myenergy.meters
        )
    )
);

CREATE POLICY "Customers and backend can update topups"
ON myenergy.topups
FOR UPDATE
TO authenticated, public_backend
USING (
    myenergy.is_backend_user()
    OR (
        meter IN (
            SELECT meters.id
            FROM myenergy.meters
        )
    )
)
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        meter IN (
            SELECT meters.id
            FROM myenergy.meters
        )
    )
);

DROP POLICY "Customers and backend can update payments" ON myenergy.payments;

CREATE POLICY "Customers and backend can insert payments"
ON myenergy.payments
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        account IN (
            SELECT customer_accounts.account
            FROM myenergy.customer_accounts
            WHERE customer_accounts.customer = myenergy.customer()
        )
    )
);

CREATE POLICY "Customers and backend can update payments"
ON myenergy.payments
FOR UPDATE
TO authenticated, public_backend
USING (
    myenergy.is_backend_user()
    OR (
        account IN (
            SELECT customer_accounts.account
            FROM myenergy.customer_accounts
            WHERE customer_accounts.customer = myenergy.customer()
        )
    )
)
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        account IN (
            SELECT customer_accounts.account
            FROM myenergy.customer_accounts
            WHERE customer_accounts.customer = myenergy.customer()
        )
    )
);


CREATE POLICY "Customers and backend can insert topups_gifts"
ON myenergy.topups_gifts
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        gift_id IN (
            SELECT g.id
            FROM myenergy.gifts g
            JOIN myenergy.accounts a ON a.property = g.account_id
            JOIN myenergy.customer_accounts ca ON ca.account = a.id
            WHERE ca.customer = myenergy.customer()
        )
    )
);

DROP POLICY "Customers and backend can update solar credits topups" ON myenergy.topups_monthly_solar_credits;

CREATE POLICY "Customers and backend can insert topups_monthly_solar_credits"
ON myenergy.topups_monthly_solar_credits
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        month_solar_credit_id IN (
            SELECT m.id
            FROM myenergy.monthly_solar_credits m
            JOIN myenergy.accounts a ON a.property = m.property_id
            JOIN myenergy.customer_accounts ca ON ca.account = a.id
            WHERE ca.customer = myenergy.customer()
        )
    )
);


CREATE POLICY "Customers and backend can insert topups_payments"
ON myenergy.topups_payments
FOR INSERT
TO authenticated, public_backend
WITH CHECK (
    myenergy.is_backend_user()
    OR (
        payment_id IN (
            SELECT p.id
            FROM myenergy.payments p, myenergy.accounts a, myenergy.customer_accounts ca
            WHERE a.id = p.account
            AND a.id = ca.account
            AND ca.customer = myenergy.customer()
        )
    )
);

COMMIT;
