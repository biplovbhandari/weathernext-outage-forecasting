-- ============================================================================
-- Train LOGISTIC_REG
-- ============================================================================
-- Fast baseline classifier with interpretable coefficients.
-- Only uses max_iterations — tree hyperparams do not apply.
-- ============================================================================

DECLARE gcp_project  STRING  DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING  DEFAULT '${DATASET_NAME}';
DECLARE ml_max_iter  INT64   DEFAULT ${ML_MAX_ITERATIONS};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE MODEL `%s.%s.outage_predictor_logistic`

  OPTIONS (
    model_type            = 'LOGISTIC_REG',
    input_label_cols      = ['outage_event'],
    data_split_method     = 'CUSTOM',
    data_split_col        = 'data_split',
    max_iterations        = %f,
    auto_class_weights    = TRUE,
    enable_global_explain = TRUE
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
  ml_max_iter,
  gcp_project, dataset_name
);
