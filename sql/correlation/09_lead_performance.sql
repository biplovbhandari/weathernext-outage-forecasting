-- ============================================================================
-- Lead-performance table — precision, recall, F1 (Parameterized)
-- ============================================================================
-- Evaluates forecast skill at each lead hour using threshold-based binary
-- classification. Computes confusion matrix and standard metrics.
--
-- x_wind: ws10 >= p90 OR ws925 >= p90 OR shear >= p90
-- x_hail: t700 <= 0C AND precip >= 2mm
-- y_outage: outage_ratio_6h_max >= OUTAGE_THRESHOLD
--
-- QC: only scores 6h blocks with sufficient EAGLE-I samples.
-- ============================================================================

DECLARE gcp_project       STRING  DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name      STRING  DEFAULT 'weathernext_demo';
DECLARE outage_threshold  FLOAT64 DEFAULT 0.05;
DECLARE min_samples       INT64   DEFAULT 8;
DECLARE lead_hours_arr    ARRAY<INT64> DEFAULT [24, 30, 36, 42, 48];

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.lead_performance` AS
  WITH p AS (
    SELECT * FROM `%s.%s.view_windhail_thresholds`
  ),

  z AS (
    SELECT
      v.county_fips,
      v.valid_ts,
      v.lead_hours,
      v.ws10_max_mps,
      v.ws925_max_mps,
      v.shear_0_6km_max_mps,
      v.t700_c_min,
      v.tp6_mm_max,
      v.outage_ratio_6h_max,
      v.samples_in_block,

      (v.ws10_max_mps >= p.p90_ws10
       OR v.ws925_max_mps >= p.p90_ws925
       OR v.shear_0_6km_max_mps >= p.p90_shear) AS x_wind,

      (v.t700_c_min <= 0.0
       AND v.tp6_mm_max >= 2.0) AS x_hail,

      (v.outage_ratio_6h_max >= @outage_threshold) AS y_outage
    FROM `%s.%s.view_outage_vs_wx_6h_qc` v
    JOIN p USING (county_fips)
    WHERE v.lead_hours IN UNNEST(@lead_hours_arr)
  ),

  scored AS (
    SELECT * FROM z
    WHERE samples_in_block >= @min_samples
  )

  SELECT
    'COMBO(W OR H)' AS model,
    county_fips,
    lead_hours,
    COUNT(*) AS n_scored,
    SUM(CASE WHEN (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END) AS TP,
    SUM(CASE WHEN (x_wind OR x_hail) AND NOT y_outage THEN 1 ELSE 0 END) AS FP,
    SUM(CASE WHEN NOT (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END) AS FN,
    SUM(CASE WHEN NOT (x_wind OR x_hail) AND NOT y_outage THEN 1 ELSE 0 END) AS TN,
    SAFE_DIVIDE(
      SUM(CASE WHEN (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END),
      NULLIF(SUM(CASE WHEN (x_wind OR x_hail) THEN 1 ELSE 0 END), 0)
    ) AS precision,
    SAFE_DIVIDE(
      SUM(CASE WHEN (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END),
      NULLIF(SUM(CASE WHEN y_outage THEN 1 ELSE 0 END), 0)
    ) AS recall,
    SAFE_DIVIDE(
      2 * SUM(CASE WHEN (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END),
      NULLIF(
        2 * SUM(CASE WHEN (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END)
        + SUM(CASE WHEN (x_wind OR x_hail) AND NOT y_outage THEN 1 ELSE 0 END)
        + SUM(CASE WHEN NOT (x_wind OR x_hail) AND y_outage THEN 1 ELSE 0 END),
        0
      )
    ) AS f1
  FROM scored
  GROUP BY model, county_fips, lead_hours
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  outage_threshold AS outage_threshold,
  min_samples AS min_samples,
  lead_hours_arr AS lead_hours_arr;
