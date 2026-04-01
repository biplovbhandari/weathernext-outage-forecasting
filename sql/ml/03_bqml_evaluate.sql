-- ============================================================================
-- Evaluate & Explain BQML Model
-- ============================================================================
-- All results are persisted as tables so they're viewable anytime in BQ
-- Console or Looker Studio — no need to re-run SELECT queries.
--
-- Tables created:
--   bqml_evaluation      — regression metrics (MAE, R2, etc.)
--   bqml_feature_importance — which features matter most
--   bqml_predictions     — predicted vs actual ratio + severity tier
--   bqml_threshold_sweep — precision/recall/F1 at multiple cutoffs
--
-- For CLASSIFIER: uncomment the confusion matrix and ROC sections at bottom
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Regression Evaluation Metrics                                       │
-- └──────────────────────────────────────────────────────────────────────┘
-- Persists: mean_absolute_error, mean_squared_error, r2_score,
--           mean_squared_log_error, median_absolute_error, explained_variance

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_evaluation` AS
  SELECT *
  FROM ML.EVALUATE(
    MODEL `%s.%s.outage_predictor_regressor`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Feature Importance (Global Explain)                                 │
-- └──────────────────────────────────────────────────────────────────────┘
-- Shows which features contribute most to predictions.

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_feature_importance` AS
  SELECT *
  FROM ML.GLOBAL_EXPLAIN(
    MODEL `%s.%s.outage_predictor_regressor`
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Generate Predictions on Test Set                                    │
-- └──────────────────────────────────────────────────────────────────────┘
-- Predicted outage ratio + derived severity tier.
-- Thresholds applied at prediction time (not training time).

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_predictions` AS
  SELECT
    county_fips,
    valid_ts,
    lead_hours,
    outage_ratio_6h_max                AS actual_ratio,
    predicted_outage_ratio_6h_max      AS predicted_ratio,

    -- Apply thresholds at prediction time
    CASE
      WHEN predicted_outage_ratio_6h_max >= 0.15 THEN 'SEVERE'
      WHEN predicted_outage_ratio_6h_max >= 0.05 THEN 'OUTAGE'
      ELSE 'NORMAL'
    END AS predicted_tier
  FROM ML.PREDICT(
    MODEL `%s.%s.outage_predictor_regressor`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Threshold Sweep — Precision/Recall/F1 at multiple cutoffs           │
-- └──────────────────────────────────────────────────────────────────────┘
-- Evaluates classification performance at each threshold without retraining.

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_threshold_sweep` AS
  SELECT
    threshold,
    COUNT(*) AS n,
    SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END) AS TP,
    SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio <  threshold THEN 1 ELSE 0 END) AS FP,
    SUM(CASE WHEN predicted_ratio <  threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END) AS FN,
    SUM(CASE WHEN predicted_ratio <  threshold AND actual_ratio <  threshold THEN 1 ELSE 0 END) AS TN,

    SAFE_DIVIDE(
      SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END),
      NULLIF(SUM(CASE WHEN predicted_ratio >= threshold THEN 1 ELSE 0 END), 0)
    ) AS precision,

    SAFE_DIVIDE(
      SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END),
      NULLIF(SUM(CASE WHEN actual_ratio >= threshold THEN 1 ELSE 0 END), 0)
    ) AS recall,

    SAFE_DIVIDE(
      2 * SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END),
      NULLIF(
        2 * SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END)
        + SUM(CASE WHEN predicted_ratio >= threshold AND actual_ratio < threshold THEN 1 ELSE 0 END)
        + SUM(CASE WHEN predicted_ratio < threshold AND actual_ratio >= threshold THEN 1 ELSE 0 END),
        0
      )
    ) AS f1

  FROM `%s.%s.bqml_predictions`
  CROSS JOIN UNNEST([0.01, 0.03, 0.05, 0.10, 0.15, 0.20]) AS threshold
  GROUP BY threshold
  ORDER BY threshold
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Classifier Evaluation (uncomment if using classifier model)         │
-- └──────────────────────────────────────────────────────────────────────┘

-- -- Confusion Matrix (TP, FP, FN, TN)
-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE TABLE `%s.%s.bqml_confusion_matrix` AS
--   SELECT *
--   FROM ML.CONFUSION_MATRIX(
--     MODEL `%s.%s.outage_predictor_classifier`,
--     (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
--   )
-- """,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name
-- );

-- -- ROC Curve Data
-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE TABLE `%s.%s.bqml_roc_curve` AS
--   SELECT *
--   FROM ML.ROC_CURVE(
--     MODEL `%s.%s.outage_predictor_classifier`,
--     (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
--   )
-- """,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name
-- );


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Predict on New Forecast Data (operational use)                      │
-- └──────────────────────────────────────────────────────────────────────┘
-- Use this pattern for scoring new WeatherNext forecasts in production.

-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE TABLE `%s.%s.bqml_operational_predictions` AS
--   SELECT
--     county_fips,
--     valid_ts,
--     lead_hours,
--     predicted_outage_ratio_6h_max AS predicted_ratio,
--     CASE
--       WHEN predicted_outage_ratio_6h_max >= 0.15 THEN 'SEVERE'
--       WHEN predicted_outage_ratio_6h_max >= 0.05 THEN 'OUTAGE'
--       ELSE 'NORMAL'
--     END AS predicted_tier
--   FROM ML.PREDICT(
--     MODEL `%s.%s.outage_predictor_regressor`,
--     (
--       SELECT
--         ws10_max_mps,
--         ws925_max_mps,
--         shear_0_6km_max_mps,
--         updraft700_pos_max_pas,
--         tp6_mm_max,
--         t700_c_min,
--         t850_c_mean,
--         hail_flag,
--         lead_hours,
--         EXTRACT(HOUR FROM valid_ts)       AS hour_of_day,
--         EXTRACT(DAYOFWEEK FROM valid_ts)  AS day_of_week,
--         EXTRACT(MONTH FROM valid_ts)      AS month,
--         ws10_max_mps * tp6_mm_max         AS wind_precip_interaction,
--         POW(ws10_max_mps, 2)              AS wind_squared,
--         shear_0_6km_max_mps * updraft700_pos_max_pas AS shear_updraft_interaction,
--         county_fips,
--         valid_ts
--       FROM `%s.%s.view_outage_vs_wx_6h_qc`
--       WHERE valid_ts >= CURRENT_TIMESTAMP()
--         AND ws10_max_mps IS NOT NULL
--     )
--   )
-- """,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name
-- );
