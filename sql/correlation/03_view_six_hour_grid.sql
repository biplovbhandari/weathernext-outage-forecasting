-- ============================================================================
-- Canonical 6-hour grid — county x valid_time scaffold (Parameterized)
-- ============================================================================
-- Generates every (county, 6-hour valid_ts) combination for the configured
-- date range. This ensures LEFT JOINs produce rows even when outages or
-- weather data are missing — critical for balanced ML training and for
-- correctly identifying zero-outage periods.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';
DECLARE county_fips  ARRAY<STRING> DEFAULT ${COUNTY_FIPS};
DECLARE start_ts     TIMESTAMP     DEFAULT TIMESTAMP('${START_DATE} 00:00:00');
DECLARE end_ts       TIMESTAMP     DEFAULT TIMESTAMP('${END_DATE} 00:00:00');

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_six_hour_grid` AS
  WITH counties AS (
    SELECT county_fips_code AS county_fips
    FROM `%s.%s.counties_ref`
    WHERE county_fips_code IN UNNEST(@county_fips)
  )
  SELECT
    c.county_fips,
    ts AS valid_ts
  FROM counties c,
  UNNEST(
    GENERATE_TIMESTAMP_ARRAY(
      @start_ts,
      @end_ts,
      INTERVAL 6 HOUR
    )
  ) AS ts
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  county_fips AS county_fips,
  start_ts AS start_ts,
  end_ts AS end_ts;
