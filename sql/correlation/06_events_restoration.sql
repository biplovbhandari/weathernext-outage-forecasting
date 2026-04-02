-- ============================================================================
-- Event restoration table — gap-tolerant outage event detection (Parameterized)
-- ============================================================================
-- Groups consecutive outage readings into discrete events, tolerating gaps
-- of up to EVENT_GAP_MINUTES. An event starts when outage_ratio exceeds the
-- threshold and ends when it drops below (or a gap exceeds tolerance).
--
-- Output: one row per event with start/end times, duration, and peak outage.
-- Use a TABLE (not VIEW) — it is static, fast for dashboards, and required
-- by event_coverage downstream.
-- ============================================================================

DECLARE gcp_project   STRING  DEFAULT '${GCP_PROJECT}';
DECLARE dataset_name  STRING  DEFAULT '${DATASET_NAME}';
DECLARE county_fips   ARRAY<STRING> DEFAULT ${COUNTY_FIPS};
DECLARE start_ts      TIMESTAMP DEFAULT TIMESTAMP('${START_DATE} 00:00:00');
DECLARE end_ts        TIMESTAMP DEFAULT TIMESTAMP('${END_DATE} 00:00:00');
DECLARE event_out_thr FLOAT64 DEFAULT ${EVENT_OUTAGE_THRESHOLD};
DECLARE event_gap_min INT64   DEFAULT ${EVENT_GAP_MINUTES};

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.events_restoration` AS

  WITH base AS (
    SELECT county_fips, ts, outage_ratio
    FROM `%s.%s.eaglei_part`
    WHERE county_fips IN UNNEST(@county_fips)
      AND ts >= @start_ts
      AND ts <  @end_ts
  ),

  y AS (
    SELECT
      county_fips,
      ts,
      outage_ratio,
      (outage_ratio >= @event_out_thr) AS outage_on
    FROM base
  ),

  gaps AS (
    SELECT
      county_fips,
      ts,
      outage_ratio,
      outage_on,
      TIMESTAMP_DIFF(ts, LAG(ts) OVER (PARTITION BY county_fips ORDER BY ts), MINUTE) AS gap_min,
      LAG(outage_on) OVER (PARTITION BY county_fips ORDER BY ts) AS prev_outage_on
    FROM y
  ),

  starts AS (
    SELECT
      county_fips,
      ts,
      outage_on,
      CASE
        WHEN outage_on AND NOT COALESCE(prev_outage_on, FALSE) THEN 1
        WHEN outage_on AND prev_outage_on AND gap_min > @event_gap_min THEN 1
        ELSE 0
      END AS is_start
    FROM gaps
  ),

  events AS (
    SELECT
      county_fips,
      ts,
      outage_on,
      SUM(is_start) OVER (
        PARTITION BY county_fips
        ORDER BY ts
        ROWS UNBOUNDED PRECEDING
      ) AS event_id
    FROM starts
    WHERE outage_on
  )

  SELECT
    county_fips,
    event_id,
    MIN(ts) AS start_ts,
    MAX(ts) AS end_ts,
    TIMESTAMP_DIFF(MAX(ts), MIN(ts), MINUTE) AS duration_min,
    MAX(outage_ratio) AS peak_outage
  FROM events
  JOIN base USING (county_fips, ts)
  GROUP BY county_fips, event_id
""",
  gcp_project, dataset_name,
  gcp_project, dataset_name
)
USING
  county_fips AS county_fips,
  start_ts AS start_ts,
  end_ts AS end_ts,
  event_out_thr AS event_out_thr,
  event_gap_min AS event_gap_min;
