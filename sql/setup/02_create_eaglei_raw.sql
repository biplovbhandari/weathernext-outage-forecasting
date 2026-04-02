-- ============================================================================
-- Step 1: Create raw EAGLE-I outage table (Parameterized)
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';

EXECUTE IMMEDIATE FORMAT("""
  CREATE TABLE IF NOT EXISTS `%s.%s.eaglei_raw` (
    fips_code       INT64,
    county          STRING,
    state           STRING,
    customers_out   INT64,
    run_start_time  TIMESTAMP,
    total_customers INT64
  )
""", gcp_project, dataset_name);

-- Data loading is handled by setup.py (Step 4: load_table_from_uri)
