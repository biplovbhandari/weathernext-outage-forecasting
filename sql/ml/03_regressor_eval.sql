-- ============================================================================
-- Evaluate BOOSTED_TREE_REGRESSOR
-- ============================================================================
-- Regression-specific evaluation: MAE, R2, predictions with severity tiers,
-- and threshold sweep for precision/recall/F1 at multiple cutoffs.
--
-- model_name, model_suffix, model_type, eval_run_id injected by pipeline.py.
-- ============================================================================

DECLARE gcp_project   STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name  STRING DEFAULT '${DATASET_NAME}';
DECLARE model_name    STRING DEFAULT 'outage_predictor_regressor';
DECLARE model_suffix  STRING DEFAULT 'regressor';
DECLARE model_type    STRING DEFAULT 'regressor';
DECLARE eval_run_id   STRING DEFAULT 'manual';

-- Evaluation metrics (MAE, R2, MSE, explained_variance)
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

-- Predictions with severity tiers
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_predictions_%s` AS
  SELECT
    county_fips,
    valid_ts,
    lead_hours,
    outage_ratio_6h_max                AS actual_ratio,
    predicted_outage_ratio_6h_max      AS predicted_ratio,
    CASE
      WHEN predicted_outage_ratio_6h_max >= 0.15 THEN 'SEVERE'
      WHEN predicted_outage_ratio_6h_max >= 0.05 THEN 'OUTAGE'
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

-- Threshold sweep: precision/recall/F1 at multiple cutoffs
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.bqml_threshold_sweep_%s` AS
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
    ) AS f1,

    @model_type AS model_type,
    @eval_run_id AS run_id

  FROM `%s.%s.bqml_predictions_%s`
  CROSS JOIN UNNEST([0.01, 0.03, 0.05, 0.10, 0.15, 0.20]) AS threshold
  GROUP BY threshold
  ORDER BY threshold
""",
  gcp_project, dataset_name, model_suffix,
  gcp_project, dataset_name, model_suffix
)
USING model_type AS model_type, eval_run_id AS eval_run_id;
