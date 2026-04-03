-- ============================================================================
-- Step 5: Create pipeline run metadata table (Parameterized)
-- ============================================================================
-- Stores one row per pipeline phase execution for traceability.
-- Written automatically by pipeline.py after each phase completes.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';

EXECUTE IMMEDIATE FORMAT("""
  CREATE TABLE IF NOT EXISTS `%s.%s.pipeline_runs` (
    run_id            STRING    NOT NULL,
    phase             STRING    NOT NULL,
    started_at        TIMESTAMP NOT NULL,
    completed_at      TIMESTAMP NOT NULL,
    duration_seconds  FLOAT64,
    status            STRING,
    steps_completed   INT64,
    steps_failed      INT64,
    config            JSON,
    step_details      JSON,
    git_commit        STRING,
    hostname          STRING
  )
""", gcp_project, dataset_name);
