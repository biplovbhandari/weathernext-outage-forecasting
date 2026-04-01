# Looker Studio Dashboard Setup Guide

## Overview

This guide walks through connecting the BigQuery views to Looker Studio and building five dashboard pages: time series, correlation heatmap, risk map, pre-position board, and event analysis.

## Prerequisites

1. Completed the pipeline setup (`python setup.py` + `python pipeline.py --phase correlation`)
2. Created Looker-optimized views by running `looker/dashboard-views.sql`
3. A Google account with access to your BigQuery project

## Step 1: Create Dashboard

1. Go to [Looker Studio](https://lookerstudio.google.com/)
2. Click **Create** -> **Report**
3. Choose **BigQuery** as the data source
4. Navigate to your project -> dataset -> select `looker_timeseries_6h`
5. Click **Add** -> **Add to Report**

## Step 2: Add Data Sources

Add all five Looker views as separate data sources:

| Data Source Name | BigQuery View | Used For |
|-----------------|---------------|----------|
| Time Series | `looker_timeseries_6h` | Line charts (outage vs weather) |
| Correlation | `looker_correlation` | Heatmap (correlation by county/lead) |
| Risk Map | `looker_risk_map` | Geo visualization (county risk tiers) |
| Pre-Board | `looker_preboard` | Table scorecard (crew pre-positioning) |
| Events | `looker_events` | Event analysis (detection coverage) |

For each: **Add Data** -> **BigQuery** -> your project -> your dataset -> select the view.

## Step 3: Page 1 -- KPI Overview

**Layout:** 3-4 scorecards across the top, date filter below

**Scorecards:**
- Total counties monitored: `COUNT DISTINCT(county_fips)` from `looker_preboard`
- High-risk county-days: `COUNTIF(tier = 'HIGH')` from `looker_preboard`
- Events detected: `COUNTIF(any_flag_anylead = TRUE)` from `looker_events`
- Total events: `COUNT(event_id)` from `looker_events`

**Filters:**
- Date range control linked to `day_utc` or `valid_ts`
- County dropdown linked to `county_fips`

## Step 4: Page 2 -- Time Series

**Chart type:** Time series (line chart)

**Configuration:**
- Data source: `looker_timeseries_6h`
- Dimension: `valid_ts`
- Metrics: `outage_ratio_6h_max` (left axis), `ws10_max_mps` (right axis)
- Breakdown dimension: `county_name`
- Optional: Add `lead_hours` as a filter to compare forecast leads

**Additional metrics available:**
- `ws925_max_mps` -- 925 hPa wind speed
- `shear_0_6km_max_mps` -- wind shear
- `tp6_mm_max` -- 6h precipitation
- `hail_flag` -- hail indicator

**Tips:**
- Use dual Y-axes: outage ratio (0-1) on left, wind speed (m/s) on right
- Add a reference line at outage_ratio = 0.05 (the "significant outage" threshold)

## Step 5: Page 3 -- Correlation Heatmap

**Chart type:** Pivot table with conditional formatting

**Configuration:**
- Data source: `looker_correlation`
- Row dimension: `county_name`
- Column dimension: `lead_hours`
- Metrics: `r_ws10`, `r_ws925`, `r_shear`, `r_precip`, `r_t700`

**Conditional formatting (for each correlation metric):**
- r >= 0.5: dark green (strong positive correlation)
- r 0.3-0.5: light green
- r 0.1-0.3: yellow
- r < 0.1: red (weak signal)

This shows which weather features have the strongest correlation with outages, and at which lead time, for each county.

## Step 6: Page 4 -- Risk Map

**Chart type:** Geo chart (filled map)

**Configuration:**
- Data source: `looker_risk_map`
- Geo dimension: `geom` (GEOGRAPHY type -- Looker Studio supports this natively for BigQuery)
- Color dimension: `tier`
- Tooltip: `county_name`, `tier`, `ws10_daymax`, `reason_codes`

**Color mapping:**
- HIGH: Red
- MEDIUM: Yellow
- LOW: Green

**Additional columns available:**
- `wind_consistency` -- how many leads agree on wind risk
- `hail_consistency` -- how many leads agree on hail risk
- `reason_codes` -- why the tier was assigned (e.g., "WIND_MULTI_LEAD", "HAIL")

## Step 7: Page 5 -- Pre-Position Board

**Chart type:** Table with bars

**Configuration:**
- Data source: `looker_preboard`
- Columns: county_name, state_name, day_utc, tier, ws10_daymax, wind_consistency, hail_consistency, reason_codes
- Sort: `tier` (HIGH first), then `day_utc`
- Row-level conditional formatting on `tier`:
  - HIGH -> red background
  - MEDIUM -> yellow background
  - LOW -> green background

## Step 8: Page 6 -- Event Analysis

**Chart type:** Table

**Configuration:**
- Data source: `looker_events`
- Columns: county_name, event_id, start_ts, end_ts, duration_min, peak_outage, dect_24h, dect_30h, dect_36h, dect_42h, dect_48h, earliest_lead_h
- Sort: `start_ts` descending
- Conditional formatting on detection flags: TRUE -> green, FALSE -> red

**Scorecard ideas:**
- Detection rate: `COUNTIF(any_flag_anylead) / COUNT(event_id)`
- Median earliest warning: `MEDIAN(earliest_lead_h)` hours

## Adding Filters

Add interactive controls at the top of each page:

1. **Date range picker:** Link to `valid_ts` or `day_utc` dimension
2. **County selector:** Dropdown linked to `county_fips` or `county_name`
3. **Lead time selector:** Dropdown linked to `lead_hours` (for time series page)
4. **Tier filter:** Dropdown linked to `tier` (for pre-board and risk map pages)

## Sharing the Dashboard

1. Click **Share** in the top right
2. Set to "Anyone with the link can view" (for public sharing)
3. Or invite specific Google accounts
4. Viewers need BigQuery read access to the underlying views

## Calculated Fields

If needed, add these as calculated fields in Looker Studio:

```
// Wind speed in mph (for US audiences)
ws10_mph = ws10_max_mps * 2.237

// Outage percentage (more intuitive than ratio)
outage_pct = outage_ratio_6h_max * 100

// Detection rate
detection_rate = COUNTIF(any_flag_anylead) / COUNT(event_id)
```

## Troubleshooting

**"No data" in charts:** Check that the date range filter includes your data window (e.g., May 2024 for the Alabama demo).

**Geo chart not rendering:** Ensure the `geom` field is recognized as a GEOGRAPHY type. You may need to set the geo type to "Geo > Full geo" in the field settings.

**Slow queries:** Looker Studio caches results for 15 minutes by default. For large datasets, consider materializing the Looker views as tables instead of views.
