-- ============================================================================
-- Extract weather features from WeatherNext Graph (Parameterized)
-- ============================================================================
-- Configure the variables below for your area of interest, date range,
-- and forecast lead window.
--
-- COST OPTIMIZATION NOTES:
--   - Column pruning on UNNEST is critical (only select u10, v10, tp6)
--   - ST_INTERSECTS with AOI polygon filters grid cells early
--   - 00Z-only init_time reduces scans by ~75%
--   - Use --dry_run flag in bq CLI to estimate cost before running
-- ============================================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │  CONFIGURATION                                          │
-- └─────────────────────────────────────────────────────────┘
DECLARE gcp_project     STRING         DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name    STRING         DEFAULT 'weathernext_demo';
DECLARE weathernext_tbl STRING         DEFAULT 'YOUR_PROJECT.weathernext_graph_forecasts.59572747_4_0';

-- Area of interest: list of 5-digit county FIPS codes
DECLARE county_fips     ARRAY<STRING>  DEFAULT ['01051', '01101'];

-- Time window
DECLARE start_ts        TIMESTAMP      DEFAULT TIMESTAMP('2024-05-06 00:00:00');
DECLARE end_ts          TIMESTAMP      DEFAULT TIMESTAMP('2024-05-15 23:59:59');

-- Forecast lead range (hours ahead)
DECLARE min_lead        INT64          DEFAULT 24;
DECLARE max_lead        INT64          DEFAULT 48;

-- Output table name
DECLARE output_table    STRING         DEFAULT 'graph_wind_precip_hourly';

-- ┌─────────────────────────────────────────────────────────┐
-- │  EXECUTION                                              │
-- └─────────────────────────────────────────────────────────┘

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE TABLE `%s.%s.%s` AS

  WITH counties AS (
    SELECT county_fips_code, county_name, county_geom
    FROM `%s.%s.counties_ref`
    WHERE county_fips_code IN UNNEST(@county_fips)
  ),

  aoi AS (
    SELECT ST_UNION_AGG(county_geom) AS geom FROM counties
  ),

  cells AS (
    SELECT
      t.init_time,
      f.time                          AS valid_time,
      f.hours                         AS lead_hours,
      TIMESTAMP_TRUNC(f.time, HOUR)   AS hour_ts,
      f.`10m_u_component_of_wind`     AS u10,
      f.`10m_v_component_of_wind`     AS v10,
      f.total_precipitation_6hr       AS tp6_m,
      t.geography_polygon             AS cell_geom
    FROM `%s` AS t
    CROSS JOIN UNNEST(t.forecast) AS f
    JOIN aoi ON ST_INTERSECTS(t.geography_polygon, aoi.geom)
    WHERE EXTRACT(HOUR FROM t.init_time) = 0
      AND f.time >= @start_ts
      AND f.time <= @end_ts
      AND f.hours BETWEEN @min_lead AND @max_lead
  ),

  cell_features AS (
    SELECT
      init_time,
      hour_ts,
      lead_hours,
      cell_geom,
      SQRT(POW(u10, 2) + POW(v10, 2))  AS ws10_mps,
      COALESCE(tp6_m, 0.0) * 1000.0    AS tp6_mm
    FROM cells
  )

  SELECT
    c.county_fips_code AS county_fips,
    c.county_name,
    f.hour_ts,
    f.lead_hours,
    MAX(f.ws10_mps)    AS ws10_max_mps,
    AVG(f.tp6_mm)      AS tp6_mm_mean
  FROM cell_features f
  JOIN counties c ON ST_INTERSECTS(f.cell_geom, c.county_geom)
  GROUP BY county_fips, county_name, hour_ts, lead_hours
  ORDER BY county_fips, hour_ts, lead_hours
""",
  gcp_project, dataset_name, output_table,
  gcp_project, dataset_name,
  weathernext_tbl
)
USING
  county_fips AS county_fips,
  start_ts AS start_ts,
  end_ts AS end_ts,
  min_lead AS min_lead,
  max_lead AS max_lead;
