-- Verify supabase:0022_contract_signatures on pg

BEGIN;

SELECT 1
FROM information_schema.tables
WHERE table_schema = 'myenergy'
  AND table_name = 'contract_signatures';

SELECT 1
FROM information_schema.columns
WHERE table_schema = 'myenergy'
  AND table_name = 'contracts'
  AND column_name = 'signed';

SELECT 1
FROM information_schema.columns
WHERE table_schema = 'myenergy'
  AND table_name = 'contracts'
  AND column_name = 'signatures_required';

SELECT 1
WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'myenergy'
      AND table_name = 'contracts'
      AND column_name = 'signed_date'
);

SELECT 1
WHERE NOT EXISTS (
    SELECT 1
    FROM myenergy.contract_signatures cs
    JOIN myenergy.contracts c ON c.id = cs.contract
    GROUP BY c.id, c.signatures_required, c.signed
    HAVING COUNT(*) >= c.signatures_required
       AND c.signed IS NOT TRUE
);

ROLLBACK;
