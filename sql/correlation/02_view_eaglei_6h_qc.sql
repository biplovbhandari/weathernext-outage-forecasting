-- ============================================================================
-- 6-hour outage blocks with QC (Parameterized)
-- ============================================================================
-- Aggregates 15-minute EAGLE-I data into 6-hour blocks aligned to 00/06/12/18Z.
-- Block alignment matches WeatherNext's 6-hour temporal resolution.
--
-- QC: samples_in_block counts readings per block (expect ~24 at 15-min cadence).
-- Downstream steps can filter on samples_in_block >= MIN_SAMPLES_PER_BLOCK.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';
DECLARE county_fips  ARRAY<STRING> DEFAULT ['01051', '01101'];
DECLARE start_ts     TIMESTAMP     DEFAULT TIMESTAMP('2024-05-06 00:00:00');
DECLARE end_ts       TIMESTAMP     DEFAULT TIMESTAMP('2024-05-15 00:00:00');

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_eaglei_6h_qc` AS
  SELECT
    county_fips,
    TIMESTAMP_ADD(
      TIMESTAMP_TRUNC(ts, HOUR),
      INTERVAL (6 - MOD(EXTRACT(HOUR FROM ts), 6)) HOUR
    ) AS block_end_ts,
    MAX(outage_ratio)     AS outage_ratio_6h_max,
    AVG(outage_ratio)     AS outage_ratio_6h_mean,
    MAX(customers_out)    AS customers_out_6h_max,
    COUNT(*)              AS samples_in_block
  FROM `%s.%s.eaglei_part`
  WHERE county_fips IN UNNEST(@county_fips)
    AND ts >= @start_ts
    AND ts <  @end_ts
  GROUP BY county_fips, block_end_ts
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  county_fips AS county_fips,
  start_ts AS start_ts,
  end_ts AS end_ts;
