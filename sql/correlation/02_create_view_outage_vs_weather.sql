-- ============================================================================
-- Join outage data with weather forecasts (Parameterized)
-- ============================================================================

DECLARE gcp_project     STRING         DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name    STRING         DEFAULT 'weathernext_demo';
DECLARE weather_table   STRING         DEFAULT 'graph_wind_precip_hourly';
DECLARE county_fips     ARRAY<STRING>  DEFAULT ['01051', '01101'];
DECLARE start_ts        TIMESTAMP      DEFAULT TIMESTAMP('2024-05-06 00:00:00');
DECLARE end_ts          TIMESTAMP      DEFAULT TIMESTAMP('2024-05-15 23:59:59');

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_outage_vs_weather` AS
  SELECT
    o.county_fips,
    o.hour_ts,
    o.outage_ratio_hour,
    w.lead_hours,
    w.ws10_max_mps,
    w.tp6_mm_mean
  FROM `%s.%s.view_eaglei_hourly` o
  JOIN `%s.%s.%s` w
    ON o.county_fips = w.county_fips
    AND o.hour_ts = w.hour_ts
  WHERE o.county_fips IN UNNEST(@county_fips)
    AND o.hour_ts BETWEEN @start_ts AND @end_ts
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name, weather_table
)
USING
  county_fips AS county_fips,
  start_ts AS start_ts,
  end_ts AS end_ts;
