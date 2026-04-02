-- ============================================================================
-- Step 3: Create counties reference table (Parameterized)
-- ============================================================================
DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.counties_ref` AS
  SELECT
    c.county_fips_code,
    c.state_fips_code,
    s.state_name,
    c.county_name,
    c.county_geom
  FROM `bigquery-public-data.geo_us_boundaries.counties` c
  LEFT JOIN `bigquery-public-data.geo_us_boundaries.states` s
    USING (state_fips_code)
""", gcp_project, dataset_name);
