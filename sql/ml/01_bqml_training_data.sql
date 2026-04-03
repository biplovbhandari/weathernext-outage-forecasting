-- ============================================================================
-- Prepare BQML Training Data (6-hour, multi-ingredient)
-- ============================================================================
-- Creates a training table for BigQuery ML using the 6-hour master view.
-- Features include 7+ weather variables, hail flag, and interaction terms.
--
-- Label: outage_event = 1 when outage_ratio_6h_max >= threshold (default 5%)
-- QC: only uses 6h blocks with sufficient EAGLE-I samples.
-- ============================================================================

DECLARE gcp_project       STRING  DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name      STRING  DEFAULT 'weathernext_demo';
DECLARE outage_threshold  FLOAT64 DEFAULT 0.05;
DECLARE min_samples       INT64   DEFAULT 8;

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_training_data` AS
  SELECT
    -- Keys
    v.county_fips,
    v.valid_ts,

    -- Weather features
    v.ws10_max_mps,
    v.ws925_max_mps,
    v.shear_0_6km_max_mps,
    v.updraft700_pos_max_pas,
    v.tp6_mm_max,
    v.t700_c_min,
    v.t850_c_mean,
    v.hail_flag,
    v.lead_hours,

    -- Temporal features (capture diurnal & weekly patterns)
    EXTRACT(HOUR FROM v.valid_ts)       AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM v.valid_ts)  AS day_of_week,
    EXTRACT(MONTH FROM v.valid_ts)      AS month,

    -- Interaction features
    v.ws10_max_mps * v.tp6_mm_max                       AS wind_precip_interaction,
    POW(v.ws10_max_mps, 2)                               AS wind_squared,
    v.shear_0_6km_max_mps * v.updraft700_pos_max_pas     AS shear_updraft_interaction,

    -- Raw outage ratio (for regression alternative)
    v.outage_ratio_6h_max,

    -- Label (binary classification)
    CASE
      WHEN v.outage_ratio_6h_max >= @outage_threshold THEN 1
      ELSE 0
    END AS outage_event,

    -- Train/test split
    -- 80/20 split: date-based to avoid temporal leakage
    CASE
      WHEN MOD(ABS(FARM_FINGERPRINT(
             CONCAT(v.county_fips, CAST(DATE(v.valid_ts) AS STRING))
           )), 5) = 0 THEN 'TEST'
      ELSE 'TRAIN'
    END AS data_split

  FROM `%s.%s.view_outage_vs_wx_6h_qc` v

  -- QC: exclude blocks with insufficient samples
  WHERE v.samples_in_block >= @min_samples
    -- Exclude rows with missing weather data
    AND v.ws10_max_mps IS NOT NULL
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  outage_threshold AS outage_threshold,
  min_samples AS min_samples;
