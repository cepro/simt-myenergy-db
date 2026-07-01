BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA extensions;

SET search_path TO flows,extensions,myenergy,public;

SELECT extensions.plan(4);


SELECT is((SELECT current_role), 'tsdbadmin', 'intial role');

SELECT is((SELECT count(*)::int FROM contract_terms_esco), 5, 'contract_terms_esco count');

-- verify trigger catches attempt to add terms from a different esco

-- create a new contract with HMCE supply terms
INSERT INTO "myenergy"."contracts" ("id", "terms", "type") VALUES
	('eb36e4fa-7ec0-44ef-9a66-b88f191bd0ce', '24b451b7-9931-4ae3-b65b-713cb8807157', 'supply');

-- check it can't be attached to a WLCE account
SELECT throws_ok(
    $$ UPDATE myenergy.accounts
        -- contract with HMCE terms
        SET current_contract = 'eb36e4fa-7ec0-44ef-9a66-b88f191bd0ce'
        WHERE id in (
            -- only 1 account and it's supply for this customer
            select account from myenergy.customer_accounts where customer in (
                select id from myenergy.customers where email = 'plot24aowner-wlce@change.me'
            )
        ) $$,
    'Contract terms for the contract being added are not allowed for the esco this account is part of'
);

-- check can't change terms on existing WLCE contract to HMCE terms
SELECT throws_ok(
    $$ UPDATE myenergy.contracts
        -- HMCE terms
        SET terms = '24b451b7-9931-4ae3-b65b-713cb8807157'
        -- see seed.sql for this contract:
        WHERE id = 'a349ef7f-2400-4984-95ba-88a79520c52a'
        $$,
    'Contract terms are not valid for the ESCO associated with this contract and account'
);

SELECT * FROM finish();
ROLLBACK;
