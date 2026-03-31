-- ============================================================================
-- Looker Studio Dashboard Views (6-hour, multi-ingredient)
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
-- View 1: Time Series — Outage vs Weather (6h, for line charts)
-- -------------------------------------------------------
-- Dimension: valid_ts
-- Metrics: outage_ratio_6h_max, ws10_max_mps, shear, hail_flag
-- Breakdown: county_fips or lead_hours

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_timeseries_6h` AS
  SELECT
    v.county_fips,
    c.county_name,
    c.state_name,
    v.valid_ts,
    v.lead_hours,
    v.outage_ratio_6h_max,
    v.ws10_max_mps,
    v.ws925_max_mps,
    v.shear_0_6km_max_mps,
    v.tp6_mm_max,
    v.hail_flag
  FROM `%s.%s.view_outage_vs_wx_6h_qc` v
  JOIN `%s.%s.counties_ref` c
    ON v.county_fips = c.county_fips_code
  WHERE v.lead_hours IS NOT NULL
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 2: Correlation Heatmap Data
-- -------------------------------------------------------
-- Rows: county_fips
-- Columns: lead_hours
-- Values: r_ws10, r_ws925, r_shear, r_updraft, r_precip, r_t700

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_correlation` AS
  SELECT
    co.county_fips,
    c.county_name,
    co.lead_hours,
    co.n_scored,
    co.r_ws10,
    co.r_ws925,
    co.r_shear,
    co.r_updraft,
    co.r_precip,
    co.r_t700
  FROM `%s.%s.correlations` co
  JOIN `%s.%s.counties_ref` c
    ON co.county_fips = c.county_fips_code
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 3: Risk Map (for geo visualization)
-- -------------------------------------------------------
-- Geo field: geom (GEOGRAPHY)
-- Metric: tier (color), reason_codes

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_risk_map` AS
  SELECT
    d.county_fips,
    c.county_name,
    c.state_name,
    c.county_geom AS geom,
    d.day_utc,
    d.tier,
    d.ws10_daymax,
    d.wind_consistency,
    d.hail_consistency,
    d.reason_codes
  FROM `%s.%s.view_daily_plan` d
  JOIN `%s.%s.counties_ref` c
    ON d.county_fips = c.county_fips_code
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 4: Pre-Position Board (for table/scorecard)
-- -------------------------------------------------------
-- Sort by: tier DESC, day_utc
-- Color: tier (RED=HIGH, YELLOW=MEDIUM, GREEN=LOW)

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_preboard` AS
  SELECT
    d.county_fips,
    c.county_name,
    c.state_name,
    d.day_utc,
    d.tier,
    d.ws10_daymax,
    d.wind_consistency,
    d.hail_consistency,
    d.reason_codes
  FROM `%s.%s.view_daily_plan` d
  JOIN `%s.%s.counties_ref` c
    ON d.county_fips = c.county_fips_code
  ORDER BY
    CASE d.tier WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
    d.day_utc, d.county_fips
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);


-- -------------------------------------------------------
-- View 5: Events with coverage (for event analysis)
-- -------------------------------------------------------
-- Shows outage events and whether forecasts detected them

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.looker_events` AS
  SELECT
    e.county_fips,
    c.county_name,
    c.state_name,
    e.event_id,
    e.start_ts,
    e.end_ts,
    e.duration_min,
    e.peak_outage,
    e.dect_24h,
    e.dect_30h,
    e.dect_36h,
    e.dect_42h,
    e.dect_48h,
    e.any_flag_anylead,
    e.earliest_lead_h
  FROM `%s.%s.event_coverage_wx` e
  JOIN `%s.%s.counties_ref` c
    ON e.county_fips = c.county_fips_code
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name);
