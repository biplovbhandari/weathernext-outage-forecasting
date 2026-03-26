-- ============================================================================
-- Evaluate & Explain BQML Model
-- ============================================================================
-- Runs evaluation, feature importance, and generates predictions.
-- Run these queries interactively to assess model performance.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Model Evaluation Metrics                                            │
-- └──────────────────────────────────────────────────────────────────────┘
-- Returns: precision, recall, accuracy, f1_score, log_loss, roc_auc

EXECUTE IMMEDIATE FORMAT("""
  SELECT *
  FROM ML.EVALUATE(
    MODEL `%s.%s.outage_predictor_boosted`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Confusion Matrix                                                    │
-- └──────────────────────────────────────────────────────────────────────┘
-- Shows TP, FP, FN, TN counts for the test set

EXECUTE IMMEDIATE FORMAT("""
  SELECT *
  FROM ML.CONFUSION_MATRIX(
    MODEL `%s.%s.outage_predictor_boosted`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  ROC Curve Data                                                      │
-- └──────────────────────────────────────────────────────────────────────┘
-- Export this to Looker or a notebook for ROC visualization

EXECUTE IMMEDIATE FORMAT("""
  SELECT *
  FROM ML.ROC_CURVE(
    MODEL `%s.%s.outage_predictor_boosted`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Feature Importance (Global Explain)                                 │
-- └──────────────────────────────────────────────────────────────────────┘
-- Shows which features contribute most to predictions

EXECUTE IMMEDIATE FORMAT("""
  SELECT *
  FROM ML.GLOBAL_EXPLAIN(
    MODEL `%s.%s.outage_predictor_boosted`
  )
""",
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Generate Predictions on Test Set                                    │
-- └──────────────────────────────────────────────────────────────────────┘
-- Outputs predicted_outage_event + predicted probability per row

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_predictions` AS
  SELECT
    county_fips,
    hour_ts,
    outage_event                           AS actual,
    predicted_outage_event                 AS predicted,
    predicted_outage_event_probs           AS probs
  FROM ML.PREDICT(
    MODEL `%s.%s.outage_predictor_boosted`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Predict on New Forecast Data (operational use)                      │
-- └──────────────────────────────────────────────────────────────────────┘
-- Use this pattern for scoring new WeatherNext forecasts in production.
-- The CTE builds the same feature set used during training.

-- EXECUTE IMMEDIATE FORMAT("""
--   SELECT
--     county_fips,
--     hour_ts,
--     predicted_outage_event,
--     predicted_outage_event_probs
--   FROM ML.PREDICT(
--     MODEL `%s.%s.outage_predictor_boosted`,
--     (
--       SELECT
--         w.ws10_max_mps,
--         w.tp6_mm_mean,
--         w.lead_hours,
--         EXTRACT(HOUR FROM w.hour_ts)       AS hour_of_day,
--         EXTRACT(DAYOFWEEK FROM w.hour_ts)  AS day_of_week,
--         EXTRACT(MONTH FROM w.hour_ts)      AS month,
--         w.ws10_max_mps * w.tp6_mm_mean     AS wind_precip_interaction,
--         POW(w.ws10_max_mps, 2)             AS wind_squared,
--         w.county_fips,
--         w.hour_ts
--       FROM `%s.%s.graph_wind_precip_hourly` w
--       WHERE w.hour_ts >= CURRENT_TIMESTAMP()  -- future forecasts only
--     )
--   )
--   ORDER BY predicted_outage_event DESC, hour_ts
-- """,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name
-- );
