BEGIN;
SELECT plan(4);

SET search_path TO flows,extensions,public;

SELECT is((SELECT current_role), 'postgres', 'intial role');

SELECT is((SELECT count(*)::int FROM contract_terms_esco), 7, 'contract_terms_esco count');

-- verify trigger catches attempt to add terms from a different esco

-- create a new contract with HMCE supply terms
INSERT INTO "public"."contracts" ("id", "terms", "type") VALUES
	('eb36e4fa-7ec0-44ef-9a66-b88f191bd0ce', '062194b8-bf44-4aa7-9c48-c2aaec4e4bb8', 'supply');

-- check it can't be attached to a WLCE account
SELECT throws_ok(
    $$ UPDATE public.accounts 
        -- contract with HMCE terms
        SET current_contract = 'eb36e4fa-7ec0-44ef-9a66-b88f191bd0ce'
        WHERE id in (
            -- only 1 account and it's supply for this customer
            select account from public.customer_accounts where customer in (
                select id from public.customers where email = 'plot24aowner-wlce@change.me'
            )
        ) $$,
    'Contract terms for the contract being added are not allowed for the esco this account is part of'
);

-- check can't change terms on existing WLCE contract to HMCE terms
SELECT throws_ok(
    $$ UPDATE public.contracts 
        -- HMCE terms
        SET terms = '062194b8-bf44-4aa7-9c48-c2aaec4e4bb8'
        -- see seed.sql for this contract:
        WHERE id = '598f3885-000b-40c4-bfa0-8cecb082ff8f'
        $$,
    'Contract terms are not valid for the ESCO associated with this contract and account'
);

SELECT * FROM finish();
ROLLBACK;
