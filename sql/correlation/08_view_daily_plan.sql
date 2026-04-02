-- ============================================================================
-- Daily pre-position board with multi-reason risk tiers (Parameterized)
-- ============================================================================
-- Day-level planning output — one row per county per day.
--
-- Tiers:
--   HIGH:   (ws10 daymax >= county p90 AND multi-lead confirmed) OR hail
--   MEDIUM: ws10 daymax >= county p90 (single lead)
--   LOW:    neither
--
-- Includes reason_codes explaining why each tier was assigned.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name STRING DEFAULT '${DATASET_NAME}';
DECLARE start_ts     TIMESTAMP DEFAULT TIMESTAMP('${START_DATE} 00:00:00');
DECLARE end_ts       TIMESTAMP DEFAULT TIMESTAMP('${END_DATE} 00:00:00');
DECLARE lead_hours_arr  ARRAY<INT64> DEFAULT ${LEAD_HOURS};
DECLARE hail_temp_thr   FLOAT64      DEFAULT ${HAIL_TEMP_THRESHOLD};
DECLARE hail_precip_thr FLOAT64      DEFAULT ${HAIL_PRECIP_THRESHOLD};
DECLARE wind_consist_min INT64       DEFAULT ${WIND_CONSISTENCY_MIN};
DECLARE hail_consist_min INT64       DEFAULT ${HAIL_CONSISTENCY_MIN};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE VIEW `%s.%s.view_daily_plan` AS
  WITH p AS (
    SELECT * FROM `%s.%s.view_windhail_thresholds`
  ),

  per6 AS (
    SELECT
      w.county_fips,
      w.hour_ts AS valid_ts,

      MAX(w.ws10_max_mps) AS ws10_max_mps_24_48,

      COUNTIF(
        w.ws10_max_mps >= p.p90_ws10
        OR w.ws925_max_mps >= p.p90_ws925
        OR w.shear_0_6km_max_mps >= p.p90_shear
      ) AS wind_flags_leads,

      COUNTIF(
        w.t700_c_min <= @hail_temp_thr
        AND w.tp6_mm_max >= @hail_precip_thr
      ) AS hail_flags_leads

    FROM `%s.%s.graph_multi_ingredients_hourly` w
    JOIN p USING (county_fips)
    WHERE w.lead_hours IN UNNEST(@lead_hours_arr)
      AND w.hour_ts >= @start_ts
      AND w.hour_ts <  @end_ts
    GROUP BY w.county_fips, valid_ts
  ),

  daily AS (
    SELECT
      county_fips,
      DATE(valid_ts) AS day_utc,
      ROUND(MAX(ws10_max_mps_24_48), 2) AS ws10_daymax,
      SUM(wind_flags_leads) AS wind_consistency,
      SUM(hail_flags_leads) AS hail_consistency
    FROM per6
    GROUP BY county_fips, day_utc
  )

  SELECT
    dly.county_fips,
    dly.day_utc,
    CASE
      WHEN (dly.ws10_daymax >= p.p90_ws10 AND dly.wind_consistency >= @wind_consist_min)
        OR dly.hail_consistency >= @hail_consist_min
      THEN 'HIGH'
      WHEN dly.ws10_daymax >= p.p90_ws10
      THEN 'MEDIUM'
      ELSE 'LOW'
    END AS tier,
    dly.ws10_daymax,
    dly.wind_consistency,
    dly.hail_consistency,
    ARRAY_TO_STRING(
      ARRAY(
        SELECT r
        FROM UNNEST([
          IF(dly.ws10_daymax >= p.p90_ws10, 'wind>=county p90', NULL),
          IF(dly.ws10_daymax >= p.p90_ws10 AND dly.wind_consistency >= @wind_consist_min,
             'multi-lead-confirmed', NULL),
          IF(dly.hail_consistency >= @hail_consist_min, 'hail-ingredients', NULL)
        ]) AS r
        WHERE r IS NOT NULL
      ),
      '; '
    ) AS reason_codes
  FROM daily dly
  JOIN p USING (county_fips)
  ORDER BY dly.day_utc, dly.county_fips
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  lead_hours_arr AS lead_hours_arr,
  start_ts AS start_ts,
  end_ts AS end_ts,
  hail_temp_thr AS hail_temp_thr,
  hail_precip_thr AS hail_precip_thr,
  wind_consist_min AS wind_consist_min,
  hail_consist_min AS hail_consist_min;
