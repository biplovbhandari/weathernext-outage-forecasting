-- ============================================================================
-- Correlation table — CORR(outage, feature) by county and lead (Parameterized)
-- ============================================================================
-- Pearson correlation between each weather feature and outage severity.
-- One row per (county_fips, lead_hours).
--
-- QC: only uses 6h blocks with sufficient EAGLE-I samples.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';
DECLARE min_samples  INT64  DEFAULT ${MIN_SAMPLES_PER_BLOCK};
DECLARE lead_hours_arr ARRAY<INT64> DEFAULT ${LEAD_HOURS};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.correlations` AS
  SELECT
    county_fips,
    lead_hours,
    COUNT(*) AS n_scored,
    CORR(outage_ratio_6h_max, ws10_max_mps)           AS r_ws10,
    CORR(outage_ratio_6h_max, ws925_max_mps)           AS r_ws925,
    CORR(outage_ratio_6h_max, shear_0_6km_max_mps)     AS r_shear,
    CORR(outage_ratio_6h_max, updraft700_pos_max_pas)   AS r_updraft,
    CORR(outage_ratio_6h_max, tp6_mm_max)               AS r_precip,
    CORR(outage_ratio_6h_max, t700_c_min)               AS r_t700
  FROM `%s.%s.view_outage_vs_wx_6h_qc`
  WHERE samples_in_block >= @min_samples
    AND lead_hours IN UNNEST(@lead_hours_arr)
  GROUP BY county_fips, lead_hours
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  min_samples AS min_samples,
  lead_hours_arr AS lead_hours_arr;
