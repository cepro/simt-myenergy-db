-- Revert supabase:0026_docuseal_multi_signature from pg

BEGIN;

DROP TABLE IF EXISTS myenergy.contract_signing_submitters;

ALTER TABLE myenergy.contracts DROP COLUMN IF EXISTS audit_log_url;

ALTER TABLE myenergy.contract_terms DROP COLUMN IF EXISTS is_multi_party;

COMMIT;