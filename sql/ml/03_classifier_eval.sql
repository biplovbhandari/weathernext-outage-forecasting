-- ============================================================================
-- Evaluate Classifier Model (shared template)
-- ============================================================================
-- Classifier-specific evaluation: precision/recall/accuracy/F1/ROC AUC,
-- probability-based predictions, confusion matrix, and ROC curve.
--
-- Reused for: BOOSTED_TREE_CLASSIFIER, LOGISTIC_REG, AUTOML_CLASSIFIER
-- model_name, model_suffix, model_type, eval_run_id injected by pipeline.py.
--
-- Note: outage_event is CAST to STRING because BQML classifiers return
-- string labels internally, causing INT64/STRING mismatch otherwise.
-- ============================================================================

DECLARE gcp_project   STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name  STRING DEFAULT '${DATASET_NAME}';
DECLARE model_name    STRING DEFAULT 'outage_predictor_classifier';
DECLARE model_suffix  STRING DEFAULT 'classifier';
DECLARE model_type    STRING DEFAULT 'classifier';
DECLARE eval_run_id   STRING DEFAULT 'manual';

-- Evaluation metrics (precision, recall, accuracy, f1_score, log_loss, roc_auc)
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_evaluation_%s` AS
  SELECT *, @model_type AS model_type, @eval_run_id AS run_id
  FROM ML.EVALUATE(
    MODEL `%s.%s.%s`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name, model_suffix,
  gcp_project, dataset_name, model_name,
  gcp_project, dataset_name
)
USING model_type AS model_type, eval_run_id AS eval_run_id;

-- Feature importance
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_feature_importance_%s` AS
  SELECT *, @model_type AS model_type, @eval_run_id AS run_id
  FROM ML.GLOBAL_EXPLAIN(
    MODEL `%s.%s.%s`
  )
""",
  gcp_project, dataset_name, model_suffix,
  gcp_project, dataset_name, model_name
)
USING model_type AS model_type, eval_run_id AS eval_run_id;

-- Predictions with probability extraction and severity tiers
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_predictions_%s` AS
  SELECT
    county_fips,
    valid_ts,
    lead_hours,
    outage_event                       AS actual_event,
    predicted_outage_event             AS predicted_event,
    (SELECT prob FROM UNNEST(predicted_outage_event_probs) WHERE CAST(label AS STRING) = '1')
                                       AS predicted_probability,
    CASE
      WHEN (SELECT prob FROM UNNEST(predicted_outage_event_probs) WHERE CAST(label AS STRING) = '1') >= 0.15 THEN 'SEVERE'
      WHEN (SELECT prob FROM UNNEST(predicted_outage_event_probs) WHERE CAST(label AS STRING) = '1') >= 0.05 THEN 'OUTAGE'
      ELSE 'NORMAL'
    END AS predicted_tier,
    @model_type AS model_type,
    @eval_run_id AS run_id
  FROM ML.PREDICT(
    MODEL `%s.%s.%s`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name, model_suffix,
  gcp_project, dataset_name, model_name,
  gcp_project, dataset_name
)
USING model_type AS model_type, eval_run_id AS eval_run_id;

-- Confusion matrix
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_confusion_matrix_%s` AS
  SELECT *, @model_type AS model_type, @eval_run_id AS run_id
  FROM ML.CONFUSION_MATRIX(
    MODEL `%s.%s.%s`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name, model_suffix,
  gcp_project, dataset_name, model_name,
  gcp_project, dataset_name
)
USING model_type AS model_type, eval_run_id AS eval_run_id;

-- ROC curve
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_roc_curve_%s` AS
  SELECT *, @model_type AS model_type, @eval_run_id AS run_id
  FROM ML.ROC_CURVE(
    MODEL `%s.%s.%s`,
    (SELECT * FROM `%s.%s.bqml_training_data` WHERE data_split = 'TEST')
  )
""",
  gcp_project, dataset_name, model_suffix,
  gcp_project, dataset_name, model_name,
  gcp_project, dataset_name
)
USING model_type AS model_type, eval_run_id AS eval_run_id;
