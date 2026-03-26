-- ============================================================================
-- Collapsed signal view — max across all lead times (Parameterized)
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_outage_vs_weather_maxlead` AS
  SELECT
    county_fips,
    hour_ts,
    MAX(ws10_max_mps)  AS ws10_max_mps_24_48,
    MAX(tp6_mm_mean)   AS tp6_mm_mean_24_48
  FROM `%s.%s.view_outage_vs_weather`
  GROUP BY county_fips, hour_ts
""", gcp_project, dataset_name, gcp_project, dataset_name);
