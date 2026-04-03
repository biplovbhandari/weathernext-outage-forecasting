-- ============================================================================
-- Train AUTOML_CLASSIFIER
-- ============================================================================
-- Google-managed AutoML — highest performance but higher cost.
-- Uses budget_hours from .env. No tree hyperparams apply.
-- See docs/vertex-ai-guide.md for standalone Vertex AI alternative.
-- ============================================================================

DECLARE gcp_project   STRING  DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name  STRING  DEFAULT '${DATASET_NAME}';
DECLARE ml_budget_hrs FLOAT64 DEFAULT ${ML_BUDGET_HOURS};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE MODEL `%s.%s.outage_predictor_automl`

  OPTIONS (
    model_type            = 'AUTOML_CLASSIFIER',
    input_label_cols      = ['outage_event'],
    data_split_method     = 'CUSTOM',
    data_split_col        = 'data_split',
    budget_hours          = %f
  )

  AS SELECT
    ws10_max_mps,
    ws925_max_mps,
    shear_0_6km_max_mps,
    updraft700_pos_max_pas,
    tp6_mm_max,
    t700_c_min,
    t850_c_mean,
    hail_flag,
    lead_hours,
    hour_of_day,
    day_of_week,
    month,
    wind_precip_interaction,
    wind_squared,
    shear_updraft_interaction,
    outage_event,
    (data_split = 'TEST') AS data_split
  FROM `%s.%s.bqml_training_data`
""",
  gcp_project, dataset_name,
  ml_budget_hrs,
  gcp_project, dataset_name
);
