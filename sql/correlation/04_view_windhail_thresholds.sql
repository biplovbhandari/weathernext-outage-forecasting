-- ============================================================================
-- County-relative wind/hail thresholds — p90/p80 (Parameterized)
-- ============================================================================
-- Computes data-driven thresholds per county from the weather extraction table.
-- Replaces manual threshold tuning (WIND_THRESHOLD_LOW/HIGH etc.) with
-- statistical percentiles:
--   p90 for wind metrics (10m, 925 hPa, shear)
--   p80 for updraft proxy (more permissive since updraft is rarer)
--
-- These thresholds are used by event_coverage, daily_plan, and lead_performance.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';
DECLARE start_ts     TIMESTAMP DEFAULT TIMESTAMP('2024-05-06 00:00:00');
DECLARE end_ts       TIMESTAMP DEFAULT TIMESTAMP('2024-05-15 00:00:00');

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_windhail_thresholds` AS
  SELECT
    county_fips,
    APPROX_QUANTILES(ws10_max_mps, 11)[OFFSET(10)]          AS p90_ws10,
    APPROX_QUANTILES(ws925_max_mps, 11)[OFFSET(10)]         AS p90_ws925,
    APPROX_QUANTILES(shear_0_6km_max_mps, 11)[OFFSET(10)]   AS p90_shear,
    APPROX_QUANTILES(updraft700_pos_max_pas, 5)[OFFSET(4)]  AS p80_updraft
  FROM `%s.%s.graph_multi_ingredients_hourly`
  WHERE hour_ts >= @start_ts
    AND hour_ts <  @end_ts
  GROUP BY county_fips
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  start_ts AS start_ts,
  end_ts AS end_ts;
