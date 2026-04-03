-- ============================================================================
-- Train BOOSTED_TREE_CLASSIFIER
-- ============================================================================
-- Predicts binary outage_event (0/1) with probability scores.
-- Uses same tree hyperparams as regressor.
-- ============================================================================

DECLARE gcp_project     STRING  DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name    STRING  DEFAULT '${DATASET_NAME}';
DECLARE ml_max_iter     INT64   DEFAULT ${ML_MAX_ITERATIONS};
DECLARE ml_learn_rate   FLOAT64 DEFAULT ${ML_LEARN_RATE};
DECLARE ml_child_weight INT64   DEFAULT ${ML_MIN_TREE_CHILD_WEIGHT};
DECLARE ml_subsample    FLOAT64 DEFAULT ${ML_SUBSAMPLE};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE MODEL `%s.%s.outage_predictor_classifier`

  OPTIONS (
    model_type            = 'BOOSTED_TREE_CLASSIFIER',
    input_label_cols      = ['outage_event'],
    data_split_method     = 'CUSTOM',
    data_split_col        = 'data_split',
    max_iterations        = %f,
    learn_rate            = %f,
    min_tree_child_weight = %f,
    subsample             = %f,
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
  ml_max_iter, ml_learn_rate, ml_child_weight, ml_subsample,
  gcp_project, dataset_name
);
