-- ============================================================================
-- Master join: weather + outages + QC on 6-hour grid (Parameterized)
-- ============================================================================
-- The base view for ALL downstream analysis: events, preboard, ML, correlations.
--
-- Uses the 6-hour grid scaffold with LEFT JOINs so that:
--   - Zero-outage periods appear (outage cols are NULL)
--   - Missing weather data periods appear (weather cols are NULL)
--
-- Includes hail_flag: t700 <= ${HAIL_TEMP_THRESHOLD} AND precip >= ${HAIL_PRECIP_THRESHOLD} (freezing + moisture).
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';
DECLARE start_ts        TIMESTAMP DEFAULT TIMESTAMP('${START_DATE} 00:00:00');
DECLARE end_ts          TIMESTAMP DEFAULT TIMESTAMP('${END_DATE} 00:00:00');
DECLARE hail_temp_thr   FLOAT64   DEFAULT ${HAIL_TEMP_THRESHOLD};
DECLARE hail_precip_thr FLOAT64   DEFAULT ${HAIL_PRECIP_THRESHOLD};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_outage_vs_wx_6h_qc` AS
  WITH wx AS (
    SELECT
      county_fips,
      hour_ts AS valid_ts,
      lead_hours,
      ws10_max_mps,
      ws925_max_mps,
      shear_0_6km_max_mps,
      updraft700_pos_max_pas,
      t700_c_min,
      t700_c_mean,
      t850_c_mean,
      tp6_mm_mean,
      tp6_mm_max
    FROM `%s.%s.graph_multi_ingredients_hourly`
    WHERE hour_ts >= @start_ts
      AND hour_ts <  @end_ts
  )
  SELECT
    g.county_fips,
    g.valid_ts,
    w.lead_hours,

    -- Weather features
    w.ws10_max_mps,
    w.ws925_max_mps,
    w.shear_0_6km_max_mps,
    w.updraft700_pos_max_pas,
    w.t700_c_min,
    w.t700_c_mean,
    w.t850_c_mean,
    w.tp6_mm_mean,
    w.tp6_mm_max,

    -- Hail flag: freezing level + moisture
    IF(w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr, 1, 0) AS hail_flag,

    -- Outage (from 6-hour QC blocks)
    e.outage_ratio_6h_max,
    e.outage_ratio_6h_mean,
    e.samples_in_block,
    e.customers_out_6h_max

  FROM `%s.%s.view_six_hour_grid` g
  LEFT JOIN wx w
    ON w.county_fips = g.county_fips
    AND w.valid_ts = g.valid_ts
  LEFT JOIN `%s.%s.view_eaglei_6h_qc` e
    ON e.county_fips = g.county_fips
    AND e.block_end_ts = g.valid_ts
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  start_ts AS start_ts,
  end_ts AS end_ts,
  hail_temp_thr AS hail_temp_thr,
  hail_precip_thr AS hail_precip_thr;
