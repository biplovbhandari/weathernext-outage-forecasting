-- ============================================================================
-- Join outage data with weather forecasts (Parameterized)
-- ============================================================================
-- No WHERE clause needed: the upstream graph_wind_precip_hourly TABLE
-- is already filtered to the configured counties and date range.
-- The JOIN naturally limits results to matching rows.

DECLARE gcp_project     STRING         DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name    STRING         DEFAULT 'weathernext_demo';
DECLARE weather_table   STRING         DEFAULT 'graph_wind_precip_hourly';

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
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name, weather_table
);
