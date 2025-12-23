-- Revert migration: 0016_register_export_missing

DROP MATERIALIZED VIEW IF EXISTS flows.register_export_missing;
DROP MATERIALIZED VIEW IF EXISTS flows.register_import_missing;

SELECT delete_job(job_id) FROM timescaledb_information.jobs WHERE proc_name = 'refresh_register_export_missing';
SELECT delete_job(job_id) FROM timescaledb_information.jobs WHERE proc_name = 'refresh_register_import_missing';

DROP FUNCTION flows.refresh_register_export_missing;
DROP FUNCTION flows.refresh_register_import_missing;