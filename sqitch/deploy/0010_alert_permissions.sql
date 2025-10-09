-- Deploy supabase:0010_alert_permissions to pg

BEGIN;

GRANT SELECT ON TABLE myenergy.customers TO grafanareader;

COMMIT;
