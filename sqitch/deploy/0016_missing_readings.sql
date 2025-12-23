-- Deploy migration: 0016_register_export_missing
-- Add materialized view for reporting on missing intervals for reads

CREATE MATERIALIZED VIEW flows.register_export_missing AS
 WITH date_range AS (
         SELECT generate_series((date_trunc('day'::text, (CURRENT_DATE - '1 year'::interval)))::timestamp with time zone, date_trunc('day'::text, (CURRENT_DATE)::timestamp with time zone), '1 day'::interval) AS day
        ), expected_counts AS (
         SELECT meter_registers.register_id,
            date_trunc('day'::text, date_range.day) AS date,
            1 AS expected_count
           FROM (flows.meter_registers
             CROSS JOIN date_range)
        ), actual_counts AS (
         SELECT register_export.register_id,
            date_trunc('day'::text, register_export."timestamp") AS date,
            count(*) AS actual_count
           FROM flows.register_export
          WHERE ((register_export."timestamp" >= (CURRENT_DATE - '1 year'::interval)) AND (register_export."timestamp" < CURRENT_DATE))
          GROUP BY register_export.register_id, (date_trunc('day'::text, register_export."timestamp"))
        )
 SELECT e.register_id,
    e.date,
    COALESCE(a.actual_count, (0)::bigint) AS record_count,
    GREATEST(0, (e.expected_count - COALESCE(a.actual_count, (0)::bigint))) AS missing_count
   FROM (expected_counts e
     LEFT JOIN actual_counts a ON (((e.register_id = a.register_id) AND (e.date = a.date))))
  ORDER BY e.register_id, e.date
  WITH NO DATA;

CREATE MATERIALIZED VIEW flows.register_import_missing AS
 WITH date_range AS (
         SELECT generate_series((date_trunc('day'::text, (CURRENT_DATE - '1 year'::interval)))::timestamp with time zone, date_trunc('day'::text, (CURRENT_DATE)::timestamp with time zone), '1 day'::interval) AS day
        ), expected_counts AS (
         SELECT meter_registers.register_id,
            date_trunc('day'::text, date_range.day) AS date,
            1 AS expected_count
           FROM (flows.meter_registers
             CROSS JOIN date_range)
        ), actual_counts AS (
         SELECT register_import.register_id,
            date_trunc('day'::text, register_import."timestamp") AS date,
            count(*) AS actual_count
           FROM flows.register_import
          WHERE ((register_import."timestamp" >= (CURRENT_DATE - '1 year'::interval)) AND (register_import."timestamp" < CURRENT_DATE))
          GROUP BY register_import.register_id, (date_trunc('day'::text, register_import."timestamp"))
        )
 SELECT e.register_id,
    e.date,
    COALESCE(a.actual_count, (0)::bigint) AS record_count,
    GREATEST(0, (e.expected_count - COALESCE(a.actual_count, (0)::bigint))) AS missing_count
   FROM (expected_counts e
     LEFT JOIN actual_counts a ON (((e.register_id = a.register_id) AND (e.date = a.date))))
  ORDER BY e.register_id, e.date
  WITH NO DATA;


REFRESH MATERIALIZED view flows.register_export_missing; 
REFRESH MATERIALIZED view flows.register_import_missing; 

CREATE FUNCTION flows.refresh_register_export_missing(
    job_id integer DEFAULT NULL::integer,
    config jsonb DEFAULT NULL::jsonb
) RETURNS void
    LANGUAGE sql
    AS $$
    REFRESH MATERIALIZED VIEW flows.register_export_missing;
$$;
CREATE FUNCTION flows.refresh_register_import_missing(
    job_id integer DEFAULT NULL::integer,
    config jsonb DEFAULT NULL::jsonb
) RETURNS void
    LANGUAGE sql
    AS $$
    REFRESH MATERIALIZED VIEW flows.register_import_missing;
$$;

SELECT add_job(
    'flows.refresh_register_export_missing',
    '1d',
    -- first run is 3am the day after the migration is run:
    initial_start => (date_trunc('day', now()) + interval '27 hours')::timestamptz);
SELECT add_job(
    'flows.refresh_register_import_missing',
    '1d',
    -- first run is 3am the day after the migration is run:
    initial_start => (date_trunc('day', now()) + interval '27 hours')::timestamptz);

GRANT SELECT ON TABLE flows.register_export_missing TO grafanareader;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE flows.register_export_missing TO flows;
GRANT SELECT ON TABLE flows.register_export_missing TO tableau;

GRANT SELECT ON TABLE flows.register_import_missing TO grafanareader;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE flows.register_import_missing TO flows;
GRANT SELECT ON TABLE flows.register_import_missing TO tableau;
