-- ============================================================================
-- Train BQML Outage Prediction Model
-- ============================================================================
-- Trains a boosted tree classifier to predict outage events from
-- WeatherNext weather features. BigQuery ML handles hyperparameter
-- tuning, feature importance, and model storage automatically.
--
-- Model type options (uncomment the one you want):
--   BOOSTED_TREE_CLASSIFIER  — Best accuracy, handles nonlinear patterns
--   LOGISTIC_REG             — Fast baseline, interpretable coefficients
--   AUTOML_CLASSIFIER        — Google-managed AutoML (higher cost, best performance)
--
-- The original demo used Vertex AI AutoML and achieved:
--   Precision ~0.67, Recall ~0.89, F1 ~0.76
--
-- BQML boosted trees should reach comparable performance at lower cost.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Boosted Tree Classifier (recommended default)                       │
-- └──────────────────────────────────────────────────────────────────────┘

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE MODEL `%s.%s.outage_predictor_boosted`

  OPTIONS (
    model_type            = 'BOOSTED_TREE_CLASSIFIER',
    input_label_cols      = ['outage_event'],
    data_split_method     = 'CUSTOM',
    data_split_col        = 'data_split',
    max_iterations        = 50,
    learn_rate            = 0.1,
    min_tree_child_weight = 5,
    subsample             = 0.8,
    enable_global_explain = TRUE      -- enables feature importance
  )

  AS SELECT
    ws10_max_mps,
    tp6_mm_mean,
    lead_hours,
    hour_of_day,
    day_of_week,
    month,
    wind_precip_interaction,
    wind_squared,
    outage_event,
    data_split
  FROM `%s.%s.bqml_training_data`
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Logistic Regression (fast baseline)                                 │
-- │  Uncomment to run instead of or alongside the boosted tree.          │
-- └──────────────────────────────────────────────────────────────────────┘

-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE MODEL `%s.%s.outage_predictor_logistic`
--
--   OPTIONS (
--     model_type            = 'LOGISTIC_REG',
--     input_label_cols      = ['outage_event'],
--     data_split_method     = 'CUSTOM',
--     data_split_col        = 'data_split',
--     auto_class_weights    = TRUE,       -- handles class imbalance
--     enable_global_explain = TRUE
--   )
--
--   AS SELECT
--     ws10_max_mps,
--     tp6_mm_mean,
--     lead_hours,
--     hour_of_day,
--     day_of_week,
--     month,
--     wind_precip_interaction,
--     wind_squared,
--     outage_event,
--     data_split
--   FROM `%s.%s.bqml_training_data`
-- """,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name
-- );


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  AutoML Classifier (highest performance, higher cost)                │
-- │  See docs/vertex-ai-guide.md for standalone Vertex AI alternative.   │
-- └──────────────────────────────────────────────────────────────────────┘

-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE MODEL `%s.%s.outage_predictor_automl`
--
--   OPTIONS (
--     model_type            = 'AUTOML_CLASSIFIER',
--     input_label_cols      = ['outage_event'],
--     data_split_method     = 'CUSTOM',
--     data_split_col        = 'data_split',
--     budget_hours          = 1.0         -- training budget (cost control)
--   )
--
--   AS SELECT
--     ws10_max_mps,
--     tp6_mm_mean,
--     lead_hours,
--     hour_of_day,
--     day_of_week,
--     month,
--     wind_precip_interaction,
--     wind_squared,
--     outage_event,
--     data_split
--   FROM `%s.%s.bqml_training_data`
-- """,
--   gcp_project, dataset_name,
--   gcp_project, dataset_name
-- );
