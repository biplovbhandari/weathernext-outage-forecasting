-- ============================================================================
-- Train BQML Outage Prediction Model
-- ============================================================================
-- Trains a model to predict outage severity from WeatherNext weather features.
-- BigQuery ML handles hyperparameter tuning, feature importance, and model
-- storage automatically.
--
-- Model type options (uncomment the one you want):
--   BOOSTED_TREE_REGRESSOR   — Predicts continuous outage_ratio (0.0–1.0)
--   BOOSTED_TREE_CLASSIFIER  — Predicts binary outage_event (0/1 + probability)
--   LOGISTIC_REG             — Fast baseline, interpretable coefficients
--   AUTOML_CLASSIFIER        — Google-managed AutoML (higher cost)
--
-- Regression is the default: it predicts severity (outage_ratio_6h_max)
-- directly, and you apply operational thresholds at prediction time.
-- ============================================================================

DECLARE gcp_project    STRING  DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name   STRING  DEFAULT 'weathernext_demo';
DECLARE ml_max_iter    INT64   DEFAULT 50;
DECLARE ml_learn_rate  FLOAT64 DEFAULT 0.1;
DECLARE ml_child_weight INT64  DEFAULT 5;
DECLARE ml_subsample   FLOAT64 DEFAULT 0.8;
DECLARE ml_budget_hrs  FLOAT64 DEFAULT 1.0;

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Boosted Tree Regressor (recommended default)                       │
-- │  Predicts outage_ratio_6h_max (0.0–1.0) — apply thresholds later   │
-- └──────────────────────────────────────────────────────────────────────┘

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE MODEL `%s.%s.outage_predictor_regressor`

  OPTIONS (
    model_type            = 'BOOSTED_TREE_REGRESSOR',
    input_label_cols      = ['outage_ratio_6h_max'],
    data_split_method     = 'CUSTOM',
    data_split_col        = 'data_split',
    max_iterations        = %f,
    learn_rate            = %f,
    min_tree_child_weight = %f,
    subsample             = %f,
    enable_global_explain = TRUE
  )

  AS SELECT
    -- Weather features
    ws10_max_mps,
    ws925_max_mps,
    shear_0_6km_max_mps,
    updraft700_pos_max_pas,
    tp6_mm_max,
    t700_c_min,
    t850_c_mean,
    hail_flag,
    lead_hours,

    -- Temporal features
    hour_of_day,
    day_of_week,
    month,

    -- Interaction features
    wind_precip_interaction,
    wind_squared,
    shear_updraft_interaction,

    -- Label (continuous: 0.0–1.0)
    outage_ratio_6h_max,

    -- Train/test split (BOOL required for regressor)
    (data_split = 'TEST') AS data_split
  FROM `%s.%s.bqml_training_data`
""",
  gcp_project, dataset_name,
  ml_max_iter, ml_learn_rate, ml_child_weight, ml_subsample,
  gcp_project, dataset_name
);


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Boosted Tree Classifier (binary: outage yes/no + probability)      │
-- │  Uncomment to run instead of or alongside the regressor.            │
-- │  Uses same tree hyperparams from .env: max_iterations, learn_rate,  │
-- │  min_tree_child_weight, subsample                                   │
-- └──────────────────────────────────────────────────────────────────────┘

-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE MODEL `%s.%s.outage_predictor_classifier`
--
--   OPTIONS (
--     model_type            = 'BOOSTED_TREE_CLASSIFIER',
--     input_label_cols      = ['outage_event'],
--     data_split_method     = 'CUSTOM',
--     data_split_col        = 'data_split',
--     max_iterations        = %f,
--     learn_rate            = %f,
--     min_tree_child_weight = %f,
--     subsample             = %f,
--     enable_global_explain = TRUE
--   )
--
--   AS SELECT
--     ws10_max_mps,
--     ws925_max_mps,
--     shear_0_6km_max_mps,
--     updraft700_pos_max_pas,
--     tp6_mm_max,
--     t700_c_min,
--     t850_c_mean,
--     hail_flag,
--     lead_hours,
--     hour_of_day,
--     day_of_week,
--     month,
--     wind_precip_interaction,
--     wind_squared,
--     shear_updraft_interaction,
--     outage_event,
--     data_split
--   FROM `%s.%s.bqml_training_data`
-- """,
--   gcp_project, dataset_name,
--   ml_max_iter, ml_learn_rate, ml_child_weight, ml_subsample,
--   gcp_project, dataset_name
-- );


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  Logistic Regression (fast baseline)                                 │
-- │  Uses max_iterations from .env. Other tree params do not apply.      │
-- └──────────────────────────────────────────────────────────────────────┘

-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE MODEL `%s.%s.outage_predictor_logistic`
--
--   OPTIONS (
--     model_type            = 'LOGISTIC_REG',
--     input_label_cols      = ['outage_event'],
--     data_split_method     = 'CUSTOM',
--     data_split_col        = 'data_split',
--     max_iterations        = %f,
--     auto_class_weights    = TRUE,
--     enable_global_explain = TRUE
--   )
--
--   AS SELECT
--     ws10_max_mps,
--     ws925_max_mps,
--     shear_0_6km_max_mps,
--     updraft700_pos_max_pas,
--     tp6_mm_max,
--     t700_c_min,
--     t850_c_mean,
--     hail_flag,
--     lead_hours,
--     hour_of_day,
--     day_of_week,
--     month,
--     wind_precip_interaction,
--     wind_squared,
--     shear_updraft_interaction,
--     outage_event,
--     data_split
--   FROM `%s.%s.bqml_training_data`
-- """,
--   gcp_project, dataset_name,
--   ml_max_iter,
--   gcp_project, dataset_name
-- );


-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  AutoML Classifier (highest performance, higher cost)               │
-- │  Uses budget_hours from .env. No tree hyperparams apply.            │
-- │  See docs/vertex-ai-guide.md for standalone Vertex AI alternative.  │
-- └──────────────────────────────────────────────────────────────────────┘

-- EXECUTE IMMEDIATE FORMAT("""
--   CREATE OR REPLACE MODEL `%s.%s.outage_predictor_automl`
--
--   OPTIONS (
--     model_type            = 'AUTOML_CLASSIFIER',
--     input_label_cols      = ['outage_event'],
--     data_split_method     = 'CUSTOM',
--     data_split_col        = 'data_split',
--     budget_hours          = %f
--   )
--
--   AS SELECT
--     ws10_max_mps,
--     ws925_max_mps,
--     shear_0_6km_max_mps,
--     updraft700_pos_max_pas,
--     tp6_mm_max,
--     t700_c_min,
--     t850_c_mean,
--     hail_flag,
--     lead_hours,
--     hour_of_day,
--     day_of_week,
--     month,
--     wind_precip_interaction,
--     wind_squared,
--     shear_updraft_interaction,
--     outage_event,
--     data_split
--   FROM `%s.%s.bqml_training_data`
-- """,
--   gcp_project, dataset_name,
--   ml_budget_hrs,
--   gcp_project, dataset_name
-- );
