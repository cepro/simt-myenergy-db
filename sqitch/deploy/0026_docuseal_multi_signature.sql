-- Deploy supabase:0026_docuseal_multi_signature to pg
--
-- Multi-party (multi-submitter) DocuSeal signing for solar contracts on
-- jointly-held properties. Two signing parties (registered proprietors),
-- one shared DocuSeal submission, one combined PDF.
--
-- Three schema changes:
--
--   1. contract_terms.is_multi_party — explicit flag that gates the
--      multi-party code path on the Java side. False (single-signer) for
--      every existing terms row; a new HMCE solar terms row in seed.sql
--      flips it true for the DOCX-based template (id 4634106).
--
--   2. contracts.audit_log_url — populated by the new `submission.completed`
--      webhook handler. Carries the DocuSeal audit log URL for both
--      multi-party and (forward-compatible) single-signer contracts.
--
--   3. contract_signing_submitters — (contract, customer) → submitter slug
--      and role. One row per proprietor on a multi-party contract; the
--      slug is the per-customer signing URL (https://docuseal.co/s/{slug})
--      served inside the WebView embed. PK on (contract, customer) is
--      the concurrency backstop alongside the SELECT ... FOR UPDATE in
--      AccountsServiceImpl#createOrGetMultiSubmitterSubmission.

BEGIN;

-- 1. is_multi_party on contract_terms -------------------------------------

ALTER TABLE myenergy.contract_terms
    ADD COLUMN is_multi_party boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN myenergy.contract_terms.is_multi_party IS
    'If true, contracts using these terms require multi-submitter DocuSeal signing '
    '(one DocuSeal submission shared by all registered proprietors). UIHTMLController '
    'branches on this flag to either lazy-create a multi-submitter submission or '
    'serve the existing single-signer /d/{slug} embed.';

-- 2. audit_log_url on contracts ------------------------------------------

ALTER TABLE myenergy.contracts
    ADD COLUMN audit_log_url text;

COMMENT ON COLUMN myenergy.contracts.audit_log_url IS
    'DocuSeal submission audit log URL. Populated by the submission.completed webhook '
    'handler for multi-party contracts; forward-compatible with single-signer flows.';

-- 3. contract_signing_submitters table -----------------------------------

CREATE TABLE myenergy.contract_signing_submitters (
    contract uuid NOT NULL REFERENCES myenergy.contracts(id) ON DELETE CASCADE,
    customer uuid NOT NULL REFERENCES myenergy.customers(id) ON DELETE CASCADE,
    slug text NOT NULL,
    role text NOT NULL CHECK (role IN ('First Party', 'Second Party')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (contract, customer)
);

ALTER TABLE myenergy.contract_signing_submitters OWNER TO :"adminrole";

COMMENT ON TABLE myenergy.contract_signing_submitters IS
    'Per-customer DocuSeal submitter mapping for multi-party contracts. The slug is '
    'the opaque per-submitter signing URL (/s/{slug}) baked into the WebView embed.';
COMMENT ON COLUMN myenergy.contract_signing_submitters.slug IS
    'Opaque DocuSeal submitter slug; full signing URL is https://docuseal.co/s/{slug}.';
COMMENT ON COLUMN myenergy.contract_signing_submitters.role IS
    'DocuSeal role label. For solar contracts with two proprietors, the lex-smaller '
    'UUID gets ''First Party'' and the other gets ''Second Party'' (see spec section '
    '"Owner ordering" in specs/docuseal-multi-signature-options.md).';

ALTER TABLE myenergy.contract_signing_submitters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their own signing submitter" ON myenergy.contract_signing_submitters;
CREATE POLICY "Customers can view their own signing submitter"
    ON myenergy.contract_signing_submitters
    FOR SELECT
    TO authenticated, public_backend, grafanareader
    USING (
        myenergy.is_backend_user()
        OR customer = (SELECT id FROM myenergy.customers WHERE email = auth.session_email())
        OR EXISTS (
            SELECT 1 FROM myenergy.customers
            WHERE email = auth.session_email() AND cepro_user = true
        )
    );

-- public_backend (the PostGraphile role the accountservice backend runs as)
-- needs INSERT for the lazy-create flow in
-- AccountsServiceImpl#createOrGetMultiSubmitterSubmission. RLS policy below
-- permits backend users; the table-level GRANT is added in the same way as
-- 0024_contract_signatures_backend_grants.sql — kept here rather than as a
-- separate migration for the same reason (no PostGraphile default-privilege
-- propagation across roles).

DROP POLICY IF EXISTS "Backend can insert signing submitters" ON myenergy.contract_signing_submitters;
CREATE POLICY "Backend can insert signing submitters"
    ON myenergy.contract_signing_submitters
    FOR INSERT
    TO public_backend
    WITH CHECK (myenergy.is_backend_user());

DROP POLICY IF EXISTS "Backend can delete signing submitters" ON myenergy.contract_signing_submitters;
CREATE POLICY "Backend can delete signing submitters"
    ON myenergy.contract_signing_submitters
    FOR DELETE
    TO public_backend
    USING (myenergy.is_backend_user());

-- GRANTS for PostGraphile (public_backend runs the mutation; see migration
-- 0024_contract_signatures_backend_grants.sql header comment for rationale).
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE myenergy.contract_signing_submitters TO public_backend;

COMMIT;