-- ============================================================================
-- Step 2: Create partitioned & clustered outage table (Parameterized)
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.eaglei_part`
  PARTITION BY DATE(ts)
  CLUSTER BY county_fips
  AS
  SELECT
    LPAD(CAST(fips_code AS STRING), 5, '0')                AS county_fips,
    county,
    state,
    customers_out,
    total_customers,
    SAFE_DIVIDE(customers_out, NULLIF(total_customers, 0))  AS outage_ratio,
    TIMESTAMP(run_start_time)                               AS ts
  FROM `%s.%s.eaglei_raw`
""", gcp_project, dataset_name, gcp_project, dataset_name);
