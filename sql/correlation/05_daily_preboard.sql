-- ============================================================================
-- Daily Pre-Position Board (Parameterized)
-- ============================================================================
-- Generates a daily crew pre-positioning summary: one row per county
-- showing the worst risk score in the next 24 hours, the peak wind,
-- and a recommended action tier.
--
-- This is the primary operational output — meant to be consumed by
-- Looker Studio, exported to CSV, or queried by a downstream API.
-- ============================================================================

DECLARE gcp_project  STRING    DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING    DEFAULT 'weathernext_demo';
DECLARE board_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.daily_preboard` AS
  WITH ranked AS (
    SELECT
      r.county_fips,
      c.county_name,
      c.state_name,
      r.hour_ts,
      r.risk_score,
      r.risk_tier,
      r.ws10_max_mps_24_48,
      r.tp6_mm_mean_24_48,
      ROW_NUMBER() OVER (
        PARTITION BY r.county_fips
        ORDER BY r.risk_score DESC
      ) AS rn
    FROM `%s.%s.view_risk_scored` r
    JOIN `%s.%s.counties_ref` c
      ON r.county_fips = c.county_fips_code
    WHERE r.hour_ts >= @board_date
      AND r.hour_ts < TIMESTAMP_ADD(@board_date, INTERVAL 24 HOUR)
  )
  SELECT
    county_fips,
    county_name,
    state_name,
    hour_ts                AS peak_risk_hour,
    risk_score             AS max_risk_score,
    risk_tier              AS max_risk_tier,
    ws10_max_mps_24_48     AS peak_wind_mps,
    tp6_mm_mean_24_48      AS peak_precip_mm,
    @board_date            AS board_generated_at,

    -- Crew action recommendation
    CASE
      WHEN risk_tier = 'HIGH'   THEN 'STAGE CREWS: Pre-position repair teams in county'
      WHEN risk_tier = 'MEDIUM' THEN 'ALERT: Monitor forecasts, prepare standby crews'
      ELSE                           'NORMAL: Routine operations'
    END AS recommendation

  FROM ranked
  WHERE rn = 1
  ORDER BY max_risk_score DESC
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING board_date AS board_date;
