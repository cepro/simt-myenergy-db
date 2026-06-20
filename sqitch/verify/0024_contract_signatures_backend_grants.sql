-- Verify supabase:0024_contract_signatures_backend_grants

BEGIN;

SELECT has_table_privilege('public_backend', 'myenergy.contract_signatures', 'SELECT');
SELECT has_table_privilege('public_backend', 'myenergy.contract_signatures', 'INSERT');
SELECT has_table_privilege('public_backend', 'myenergy.contract_signatures', 'UPDATE');
SELECT has_table_privilege('public_backend', 'myenergy.contract_signatures', 'DELETE');

SELECT has_table_privilege('public_backend', 'myenergy.corporate_bodies', 'SELECT');
SELECT has_table_privilege('public_backend', 'myenergy.customer_corporate_bodies', 'SELECT');
SELECT has_table_privilege('public_backend', 'myenergy.registered_proprietors', 'SELECT');

ROLLBACK;
