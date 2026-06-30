-- Verify supabase:0026_docuseal_multi_signature on pg

BEGIN;

-- contract_terms.is_multi_party exists with default false
SELECT 1/count(*) FROM information_schema.columns
WHERE table_schema = 'myenergy'
  AND table_name = 'contract_terms'
  AND column_name = 'is_multi_party'
  AND data_type = 'boolean'
  AND column_default LIKE '%false%';

-- contracts.audit_log_url exists as nullable text
SELECT 1/count(*) FROM information_schema.columns
WHERE table_schema = 'myenergy'
  AND table_name = 'contracts'
  AND column_name = 'audit_log_url'
  AND data_type = 'text'
  AND is_nullable = 'YES';

-- contract_signing_submitters exists with the right columns
SELECT 1/count(*) FROM information_schema.tables
WHERE table_schema = 'myenergy'
  AND table_name = 'contract_signing_submitters';

SELECT 1/count(*) FROM information_schema.table_constraints
WHERE table_schema = 'myenergy'
  AND table_name = 'contract_signing_submitters'
  AND constraint_type = 'PRIMARY KEY';

-- role check constraint exists
SELECT 1/count(*) FROM information_schema.check_constraints
WHERE constraint_schema = 'myenergy'
  AND constraint_name LIKE 'contract_signing_submitters%role%';

ROLLBACK;