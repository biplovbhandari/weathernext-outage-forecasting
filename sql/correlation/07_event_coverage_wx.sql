-- ============================================================================
-- Event coverage table — "did we detect this event?" (Parameterized)
-- ============================================================================
-- For each outage event from events_restoration, checks whether weather
-- forecasts at each lead hour (24/30/36/42/48) flagged elevated risk.
--
-- Wind flag: ws10 >= p90 OR ws925 >= p90 OR shear >= p90
-- Hail flag: t700 <= 0C AND precip >= 2mm
--
-- Output: per-event detection flags at each lead, earliest detection lead,
-- and duration. Used for evaluating forecast utility.
-- ============================================================================

DECLARE gcp_project  STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name STRING DEFAULT 'weathernext_demo';
DECLARE start_ts        TIMESTAMP DEFAULT TIMESTAMP('2024-05-06 00:00:00');
DECLARE end_ts          TIMESTAMP DEFAULT TIMESTAMP('2024-05-15 00:00:00');
DECLARE hail_temp_thr   FLOAT64   DEFAULT 0.0;
DECLARE hail_precip_thr FLOAT64   DEFAULT 2.0;

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.event_coverage_wx` AS

  WITH per_event AS (
    SELECT
      county_fips,
      event_id,
      start_ts,
      end_ts,
      peak_outage
    FROM `%s.%s.events_restoration`
  ),

  -- Align event boundaries to 6-hour blocks
  event_blocks AS (
    SELECT
      county_fips,
      event_id,
      start_ts,
      end_ts,
      peak_outage,
      TIMESTAMP_ADD(
        TIMESTAMP_TRUNC(start_ts, HOUR),
        INTERVAL (6 - MOD(EXTRACT(HOUR FROM start_ts), 6)) HOUR
      ) AS start_block_end,
      TIMESTAMP_ADD(
        TIMESTAMP_TRUNC(end_ts, HOUR),
        INTERVAL (6 - MOD(EXTRACT(HOUR FROM end_ts), 6)) HOUR
      ) AS end_block_end
    FROM per_event
  ),

  p AS (
    SELECT * FROM `%s.%s.view_windhail_thresholds`
  ),

  -- Check weather flags at each (county, valid_ts, lead_hours)
  wx_flags AS (
    SELECT
      w.county_fips,
      w.hour_ts AS valid_ts,

      MAX(IF(w.lead_hours = 24 AND (
        w.ws10_max_mps >= p.p90_ws10 OR
        w.ws925_max_mps >= p.p90_ws925 OR
        w.shear_0_6km_max_mps >= p.p90_shear
      ), 1, 0)) AS wind24,
      MAX(IF(w.lead_hours = 30 AND (
        w.ws10_max_mps >= p.p90_ws10 OR
        w.ws925_max_mps >= p.p90_ws925 OR
        w.shear_0_6km_max_mps >= p.p90_shear
      ), 1, 0)) AS wind30,
      MAX(IF(w.lead_hours = 36 AND (
        w.ws10_max_mps >= p.p90_ws10 OR
        w.ws925_max_mps >= p.p90_ws925 OR
        w.shear_0_6km_max_mps >= p.p90_shear
      ), 1, 0)) AS wind36,
      MAX(IF(w.lead_hours = 42 AND (
        w.ws10_max_mps >= p.p90_ws10 OR
        w.ws925_max_mps >= p.p90_ws925 OR
        w.shear_0_6km_max_mps >= p.p90_shear
      ), 1, 0)) AS wind42,
      MAX(IF(w.lead_hours = 48 AND (
        w.ws10_max_mps >= p.p90_ws10 OR
        w.ws925_max_mps >= p.p90_ws925 OR
        w.shear_0_6km_max_mps >= p.p90_shear
      ), 1, 0)) AS wind48,

      MAX(IF(w.lead_hours = 24 AND (w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr), 1, 0)) AS hail24,
      MAX(IF(w.lead_hours = 30 AND (w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr), 1, 0)) AS hail30,
      MAX(IF(w.lead_hours = 36 AND (w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr), 1, 0)) AS hail36,
      MAX(IF(w.lead_hours = 42 AND (w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr), 1, 0)) AS hail42,
      MAX(IF(w.lead_hours = 48 AND (w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr), 1, 0)) AS hail48,

      MIN(
        IF(
          (w.ws10_max_mps >= p.p90_ws10
           OR w.ws925_max_mps >= p.p90_ws925
           OR w.shear_0_6km_max_mps >= p.p90_shear)
          OR
          (w.t700_c_min <= @hail_temp_thr AND w.tp6_mm_max >= @hail_precip_thr),
          w.lead_hours,
          NULL
        )
      ) AS earliest_lead_h

    FROM `%s.%s.graph_multi_ingredients_hourly` w
    JOIN p USING (county_fips)
    WHERE w.hour_ts >= @start_ts
      AND w.hour_ts <  @end_ts
    GROUP BY w.county_fips, valid_ts
  )

  SELECT
    e.county_fips,
    e.event_id,
    e.start_ts,
    e.end_ts,
    TIMESTAMP_DIFF(e.end_ts, e.start_ts, MINUTE) AS duration_min,
    e.peak_outage,

    -- Detection flags per lead hour (wind OR hail)
    GREATEST(COALESCE(MAX(wx.wind24),0), COALESCE(MAX(wx.hail24),0)) AS dect_24h,
    GREATEST(COALESCE(MAX(wx.wind30),0), COALESCE(MAX(wx.hail30),0)) AS dect_30h,
    GREATEST(COALESCE(MAX(wx.wind36),0), COALESCE(MAX(wx.hail36),0)) AS dect_36h,
    GREATEST(COALESCE(MAX(wx.wind42),0), COALESCE(MAX(wx.hail42),0)) AS dect_42h,
    GREATEST(COALESCE(MAX(wx.wind48),0), COALESCE(MAX(wx.hail48),0)) AS dect_48h,

    -- Any detection at any lead?
    COALESCE(
      MAX(
        IF(
          (wx.wind24+wx.wind30+wx.wind36+wx.wind42+wx.wind48
           + wx.hail24+wx.hail30+wx.hail36+wx.hail42+wx.hail48) > 0,
          1, 0
        )
      ),
      0
    ) AS any_flag_anylead,

    MIN(wx.earliest_lead_h) AS earliest_lead_h

  FROM event_blocks e
  LEFT JOIN wx_flags wx
    ON wx.county_fips = e.county_fips
    AND wx.valid_ts BETWEEN e.start_block_end AND e.end_block_end
  GROUP BY e.county_fips, e.event_id, e.start_ts, e.end_ts, e.peak_outage
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
