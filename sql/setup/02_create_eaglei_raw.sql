-- ============================================================================
-- Step 1: Create raw EAGLE-I outage table (Parameterized)
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';

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

-- Load data via bq CLI (run from shell):
-- bq load \
--   --source_format=CSV \
--   --field_delimiter=',' \
--   --skip_leading_rows=1 \
--   --autodetect \
--   ${GCP_PROJECT}:${DATASET_NAME}.eaglei_raw \
--   gs://${GCS_BUCKET}/eaglei_outages_2024.csv
