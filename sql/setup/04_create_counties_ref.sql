-- ============================================================================
-- Step 3: Create counties reference table (Parameterized)
-- ============================================================================
-- Optional: filter to specific states for smaller reference table

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';
-- Set to NULL for all US counties, or e.g. ['Alabama', 'Georgia'] to filter
DECLARE target_states ARRAY<STRING> DEFAULT NULL;

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

-- If you want to filter by state, run this instead:
-- CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET.counties_ref` AS
-- SELECT c.county_fips_code, c.state_fips_code, s.state_name,
--        c.county_name, c.county_geom
-- FROM `bigquery-public-data.geo_us_boundaries.counties` c
-- LEFT JOIN `bigquery-public-data.geo_us_boundaries.states` s
--   USING (state_fips_code)
-- WHERE s.state_name IN UNNEST(@target_states);
