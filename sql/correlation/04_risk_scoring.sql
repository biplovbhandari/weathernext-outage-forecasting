-- ============================================================================
-- Risk Scoring (Parameterized)
-- ============================================================================
-- Computes a composite risk score per county-hour based on:
--   - Normalized wind speed (0–1)
--   - Normalized precipitation (0–1)
--   - Optional icing proxy flag
--
-- Risk formula: Risk = 0.7 * wind_norm + 0.3 * precip_norm
-- These weights can be tuned per region based on correlation analysis.
--
-- Output: risk-ranked county list for crew pre-positioning decisions.
-- ============================================================================

DECLARE gcp_project  STRING  DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING  DEFAULT 'weathernext_demo';

-- Normalization thresholds (adjust based on regional climatology)
DECLARE wind_low     FLOAT64 DEFAULT 5.0;    -- m/s — below this = negligible
DECLARE wind_high    FLOAT64 DEFAULT 25.0;   -- m/s — at/above this = max risk
DECLARE precip_low   FLOAT64 DEFAULT 0.0;    -- mm
DECLARE precip_high  FLOAT64 DEFAULT 50.0;   -- mm — heavy 6h accumulation

-- Risk weights
DECLARE w_wind       FLOAT64 DEFAULT 0.7;
DECLARE w_precip     FLOAT64 DEFAULT 0.3;

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_risk_scored` AS
  WITH base AS (
    SELECT
      county_fips,
      hour_ts,
      ws10_max_mps_24_48,
      tp6_mm_mean_24_48,

      -- Normalize wind: clamp to [0, 1]
      LEAST(1.0, GREATEST(0.0,
        (ws10_max_mps_24_48 - %f) / NULLIF(%f - %f, 0)
      )) AS wind_norm,

      -- Normalize precip: clamp to [0, 1]
      LEAST(1.0, GREATEST(0.0,
        (tp6_mm_mean_24_48 - %f) / NULLIF(%f - %f, 0)
      )) AS precip_norm

    FROM `%s.%s.view_outage_vs_weather_maxlead`
  ),
  scored AS (
    SELECT
      *,
      (%f * wind_norm + %f * precip_norm) AS risk_score
    FROM base
  )
  SELECT
    county_fips,
    hour_ts,
    ws10_max_mps_24_48,
    tp6_mm_mean_24_48,
    wind_norm,
    precip_norm,
    risk_score,

    CASE
      WHEN risk_score >= 0.7 THEN 'HIGH'
      WHEN risk_score >= 0.4 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS risk_tier

  FROM scored
""",
  gcp_project, dataset_name,
  wind_low, wind_high, wind_low,
  precip_low, precip_high, precip_low,
  gcp_project, dataset_name,
  w_wind, w_precip
);
