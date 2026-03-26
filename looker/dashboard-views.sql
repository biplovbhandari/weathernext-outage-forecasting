-- ============================================================================
-- Looker Studio Dashboard Views
-- ============================================================================
-- These views are optimized for connecting to Looker Studio.
-- Each view maps to one data source / chart in the dashboard.
--
-- See docs/looker-studio-guide.md for setup instructions.
-- ============================================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │  CONFIGURATION                                          │
-- └─────────────────────────────────────────────────────────┘
DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';


-- -------------------------------------------------------
-- View 1: Time Series — Outage vs Wind (for line charts)
-- -------------------------------------------------------
-- Use in Looker: Time series chart
-- Dimension: hour_ts
-- Metrics: outage_ratio_hour, ws10_max_mps, tp6_mm_mean
-- Breakdown: county_fips (or lead_hours for multi-lead comparison)

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_timeseries` AS
  SELECT
    o.county_fips,
    c.county_name,
    c.state_name,
    o.hour_ts,
    o.outage_ratio_hour,
    w.lead_hours,
    w.ws10_max_mps,
    w.tp6_mm_mean
  FROM `%s.%s.view_outage_vs_weather` o
  JOIN `%s.%s.counties_ref` c
    ON o.county_fips = c.county_fips_code
  LEFT JOIN `%s.%s.graph_wind_precip_hourly` w
    ON o.county_fips = w.county_fips
    AND o.hour_ts = w.hour_ts
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 2: Correlation Heatmap Data
-- -------------------------------------------------------
-- Use in Looker: Pivot table or heatmap
-- Rows: county_fips
-- Columns: lead_hours
-- Values: r_wind, r_precip

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_correlation` AS
  SELECT
    v.county_fips,
    c.county_name,
    v.lead_hours,
    CORR(v.outage_ratio_hour, v.ws10_max_mps) AS r_wind,
    CORR(v.outage_ratio_hour, v.tp6_mm_mean)  AS r_precip,
    COUNT(*)                                    AS n_hours
  FROM `%s.%s.view_outage_vs_weather` v
  JOIN `%s.%s.counties_ref` c
    ON v.county_fips = c.county_fips_code
  GROUP BY v.county_fips, c.county_name, v.lead_hours
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 3: Risk Map (for geo visualization)
-- -------------------------------------------------------
-- Use in Looker: Geo chart / filled map
-- Geo field: geom (GEOGRAPHY)
-- Metric: max_risk_score (color intensity)

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_risk_map` AS
  SELECT
    r.county_fips,
    c.county_name,
    c.state_name,
    c.county_geom AS geom,
    r.max_risk_score,
    r.max_risk_tier,
    r.peak_wind_mps,
    r.peak_precip_mm,
    r.recommendation
  FROM `%s.%s.daily_preboard` r
  JOIN `%s.%s.counties_ref` c
    ON r.county_fips = c.county_fips_code
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 4: Pre-Position Board (for table/scorecard)
-- -------------------------------------------------------
-- Use in Looker: Table with conditional formatting
-- Sort by: max_risk_score DESC
-- Color: risk_tier (RED=HIGH, YELLOW=MEDIUM, GREEN=LOW)

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_preboard` AS
  SELECT
    county_fips,
    county_name,
    state_name,
    peak_risk_hour,
    max_risk_score,
    max_risk_tier,
    peak_wind_mps,
    peak_precip_mm,
    recommendation,
    board_generated_at
  FROM `%s.%s.daily_preboard`
  ORDER BY max_risk_score DESC
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name);
