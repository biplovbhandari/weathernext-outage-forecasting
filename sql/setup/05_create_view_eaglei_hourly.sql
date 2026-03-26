-- ============================================================================
-- Step 4: Hourly outage aggregation view (Parameterized)
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_eaglei_hourly` AS
  WITH hourly AS (
    SELECT
      county_fips,
      TIMESTAMP_TRUNC(ts, HOUR) AS hour_ts,
      AVG(outage_ratio)         AS outage_ratio_hour
    FROM `%s.%s.eaglei_part`
    GROUP BY county_fips, hour_ts
  )
  SELECT
    h.county_fips,
    h.hour_ts,
    h.outage_ratio_hour,
    c.state_name,
    c.county_name,
    c.county_geom AS geom
  FROM hourly h
  JOIN `%s.%s.counties_ref` c
    ON h.county_fips = c.county_fips_code
""", gcp_project, dataset_name,
     gcp_project, dataset_name,
     gcp_project, dataset_name);
