-- ============================================================================
-- Prepare BQML Training Data
-- ============================================================================
-- Creates a training table for BigQuery ML by joining weather features
-- with outage labels. The target variable is a binary classification:
--   outage_event = 1 when outage_ratio >= threshold (default 5%)
--
-- Features: wind speed, precipitation, lead time, hour-of-day, day-of-week
-- Label: outage_event (binary)
--
-- This table is in the subsequent ml steps.
-- ============================================================================

DECLARE gcp_project       STRING  DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name      STRING  DEFAULT 'weathernext_demo';
DECLARE outage_threshold  FLOAT64 DEFAULT 0.05;  -- 5% of customers

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_training_data` AS
  SELECT
    -- ─── Keys ────────────────────────────────────
    o.county_fips,
    o.hour_ts,

    -- ─── Features ────────────────────────────────
    w.ws10_max_mps,
    w.tp6_mm_mean,
    w.lead_hours,

    -- Temporal features (capture diurnal & weekly patterns)
    EXTRACT(HOUR FROM o.hour_ts)       AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM o.hour_ts)  AS day_of_week,
    EXTRACT(MONTH FROM o.hour_ts)      AS month,

    -- Interaction features
    w.ws10_max_mps * w.tp6_mm_mean     AS wind_precip_interaction,
    POW(w.ws10_max_mps, 2)             AS wind_squared,

    -- Raw outage ratio (for regression alternative)
    o.outage_ratio_hour,

    -- ─── Label (binary classification) ───────────
    CASE
      WHEN o.outage_ratio_hour >= @outage_threshold THEN 1
      ELSE 0
    END AS outage_event,

    -- ─── Train/test split ────────────────────────
    -- 80/20 split: use date-based splitting to avoid temporal leakage
    CASE
      WHEN MOD(ABS(FARM_FINGERPRINT(
             CONCAT(o.county_fips, CAST(DATE(o.hour_ts) AS STRING))
           )), 5) = 0 THEN 'TEST'
      ELSE 'TRAIN'
    END AS data_split

  FROM `%s.%s.view_eaglei_hourly` o
  JOIN `%s.%s.graph_wind_precip_hourly` w
    ON o.county_fips = w.county_fips
    AND o.hour_ts = w.hour_ts

  -- Exclude rows with missing weather data
  WHERE w.ws10_max_mps IS NOT NULL
    AND w.tp6_mm_mean IS NOT NULL
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING outage_threshold AS outage_threshold;
