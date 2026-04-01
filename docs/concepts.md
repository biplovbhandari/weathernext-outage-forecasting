# Key Concepts

## WeatherNext

WeatherNext is Google DeepMind's AI-powered weather forecasting system. Unlike traditional Numerical Weather Prediction (NWP) models that solve physical equations on supercomputers, WeatherNext uses a graph neural network trained on decades of ERA5 reanalysis data to produce forecasts in seconds.

### WeatherNext Graph (Deterministic)

The "Graph" model produces a single deterministic forecast -- one predicted value for each variable at each grid point and time step. This is what we use in this project.

Key characteristics:

- **Forecast horizon:** 10 days (240 hours)
- **Temporal resolution:** 6-hourly steps (valid times at 00, 06, 12, 18 UTC)
- **Spatial resolution:** ~0.25 degree grid (roughly 25 km at mid-latitudes)
- **Variables:** ~89 bands including wind, temperature, precipitation, pressure, humidity at multiple levels
- **Access:** BigQuery Analytics Hub subscription
- **Table structure:** Partitioned by `init_time`, clustered by `geography`

### WeatherNext Gen (Ensemble)

The "Gen" model produces multiple ensemble members -- each a plausible future weather scenario. This enables probabilistic forecasting ("30% chance of wind exceeding 20 m/s"). Not used in this project's current version but planned for future work.

### Reading Forecasts in BigQuery

The forecast table has a nested schema. Each row is one grid point at one initialization time:

```
init_time: TIMESTAMP           -- When the forecast was made (e.g., 2024-05-06 00:00:00 UTC)
geography: GEOGRAPHY           -- Grid point center (POINT) -- CLUSTER KEY
geography_polygon: GEOGRAPHY   -- Grid cell boundary (POLYGON)
forecast: ARRAY<STRUCT>        -- Nested forecast array (~89 bands)
  |-- time: TIMESTAMP          -- Valid time of this forecast step
  |-- hours: INT64             -- Lead hours (0, 6, 12, ... 240)
  |-- 10m_u_component_of_wind: FLOAT64
  |-- 10m_v_component_of_wind: FLOAT64
  |-- total_precipitation_6hr: FLOAT64
  |-- 2m_temperature: FLOAT64
  |-- {level}_temperature: FLOAT64       -- at 700, 850, 925, 1000 hPa
  |-- {level}_u_component_of_wind: FLOAT64
  |-- {level}_v_component_of_wind: FLOAT64
  |-- {level}_vertical_velocity: FLOAT64
  +-- ... (many more fields)
```

To access individual forecast steps, you must `CROSS JOIN UNNEST(forecast)`. Always use column pruning -- selecting only the fields you need -- to control query costs.

## EAGLE-I

EAGLE-I (Environment for Analysis of Geo-Located Energy Information) is a US Department of Energy platform that tracks power outages across the United States in near-real-time.

Key characteristics:

- **Granularity:** County-level, 15-minute intervals
- **Coverage:** All US states
- **Key fields:** customers_out, total_customers
- **Derived metric:** `outage_ratio = customers_out / total_customers`

An outage_ratio of 0.05 means 5% of customers in a county are without power. Values above this threshold typically indicate a significant weather event.

## 6-Hour Alignment and QC

WeatherNext forecasts at 6-hour temporal resolution (valid at 00, 06, 12, 18 UTC). EAGLE-I reports at 15-minute intervals. To join them, we aggregate EAGLE-I into 6-hour blocks aligned to the same boundaries.

**Block construction:**
Each 6-hour block (e.g., 06:00-12:00 UTC) aggregates all 15-minute readings within it:

- `outage_ratio_6h_max` -- peak outage ratio (captures brief spikes)
- `outage_ratio_6h_mean` -- average outage ratio
- `customers_out_6h_max` -- peak customers affected
- `samples_in_block` -- count of 15-minute readings (expect ~24 at full cadence)

**Quality control:**
Blocks with fewer than `MIN_SAMPLES_PER_BLOCK` readings (default: 8) are flagged as low-quality. This handles gaps in EAGLE-I data (maintenance windows, reporting outages). Downstream analysis steps (lead_performance, correlations) only use blocks passing the QC threshold.

### 6-Hour Grid Scaffold

A canonical grid of every (county, 6-hour timestamp) combination ensures balanced LEFT JOINs. Without this scaffold, zero-outage periods and missing-weather periods would silently disappear from the data -- causing biased ML training and incorrect correlation calculations.

## Multi-Ingredient Weather Features

Beyond basic 10m wind, we extract multiple weather ingredients that correlate with outage risk:


| Feature                 | Variable       | Why it matters                                     |
| ----------------------- | -------------- | -------------------------------------------------- |
| 10m wind speed          | `ws10`         | Direct tree/infrastructure damage                  |
| 925 hPa wind speed      | `ws925`        | Low-level jet indicator (stronger winds aloft)     |
| 0-6 km wind shear       | `shear`        | Severe storm potential (supercells, tornadoes)     |
| 700 hPa updraft proxy   | `updraft700`   | Convective activity (thunderstorm strength)        |
| Hail flag               | `hail_flag`    | t700 <= 0C AND precip >= 2mm (freezing + moisture) |
| 6h precipitation        | `tp6`          | Flooding, ground saturation (weakens tree roots)   |
| 700/850 hPa temperature | `t700`, `t850` | Icing risk, atmospheric stability                  |


Wind speed is computed from u/v vector components: `SQRT(u^2 + v^2)`. Wind shear is the difference between 925 hPa and 10m wind speeds.

## Per-County Thresholds

Instead of manually tuning fixed thresholds (e.g., "wind > 17 m/s = high risk"), we compute data-driven percentiles from the weather extraction for each county:

- **p90** for wind metrics (10m, 925 hPa, shear) -- flags the top 10% of weather
- **p80** for updraft proxy (more permissive since updraft events are rarer)

This is important because a coastal county regularly sees 15 m/s winds (normal for that region), while an inland county might consider 10 m/s unusual. Per-county thresholds capture this local climatology automatically.

Thresholds are computed by `view_windhail_thresholds` from the extracted weather data and are used by event coverage, daily plan, and lead performance steps.

## Spatial Joins in BigQuery

### The Problem

WeatherNext forecasts are on a regular global grid. Utility service territories follow county boundaries. We need to map grid cells to counties.

### The Solution

BigQuery GIS provides `ST_INTERSECTS(geometry_a, geometry_b)` which returns TRUE if two geographic shapes overlap. We use a two-stage approach for cost optimization:

1. **Pre-compute AOI** -- Merge target county polygons (with spatial buffer) into a single geometry stored as a DECLARE variable
2. **Cluster-pruned scan** -- `ST_INTERSECTS(t.geography, target_aoi)` leverages the geography cluster index, dramatically reducing rows read before UNNEST

A spatial buffer (`SPATIAL_BUFFER_M`, default 25 km) around county boundaries ensures we capture grid cells at the edges.

### Aggregation Strategy

After matching grid cells to counties, we aggregate:

- **Wind:** `MAX(wind_speed)` -- the worst wind anywhere in the county
- **Precipitation:** both `MAX` and `AVG` -- peak and mean across the county
- **Temperature:** `MIN` (for icing) and `MEAN`

## Event Detection

Gap-tolerant outage event detection groups consecutive EAGLE-I readings with elevated outage ratios into discrete events.

**Parameters:**

- `EVENT_OUTAGE_THRESHOLD` (default: 0.005 = 0.5%) -- minimum outage_ratio to start/continue an event
- `EVENT_GAP_MINUTES` (default: 60) -- maximum gap between readings before splitting into separate events

**Output:** One row per event with:

- Start and end timestamps
- Duration in minutes
- Peak outage ratio
- County FIPS

Events are used for forecast validation: "Did the forecast at 24h lead detect this outage event?"

## Event Coverage and Forecast Validation

For each detected outage event, we check whether weather forecasts flagged elevated risk:

- **Wind flag:** ws10 >= p90 OR ws925 >= p90 OR shear >= p90 (any wind metric exceeds threshold)
- **Hail flag:** t700 <= 0C AND precip >= 2mm

Detection is checked at each configured lead hour (24, 30, 36, 42, 48h). Output includes:

- Per-lead detection flags (`dect_24h`, `dect_30h`, etc.)
- Whether any lead flagged the event (`any_flag_anylead`)
- The earliest lead that detected it (`earliest_lead_h`)

## Forecast Leads

A forecast's "lead time" is how far ahead it predicts. A 24-hour lead means the forecast was made 24 hours before the predicted event.

Configurable via `LEAD_HOURS` (default: `24,30,36,42,48`). These are 6-hour increments matching WeatherNext's temporal resolution.

**Lead performance** is evaluated separately at each lead hour:

- **Precision** -- of all "flagged" forecasts, how many had actual outages?
- **Recall** -- of all actual outages, how many were flagged?
- **F1** -- harmonic mean of precision and recall

Typically, 24h forecasts are more skillful than 48h, but both provide actionable lead time for crew mobilization.

## Risk Scoring (Daily Plan)

The daily plan assigns risk tiers per county per day:

- **HIGH:** Wind daymax >= county p90 confirmed by multiple forecast leads, OR hail flagged by multiple leads
- **MEDIUM:** Wind daymax >= county p90 from a single forecast lead
- **LOW:** Neither condition met

Includes `reason_codes` (e.g., "WIND_MULTI_LEAD", "HAIL") and consistency scores showing how many leads agree on the risk signal. This replaces the earlier fixed-weight approach with a more transparent, multi-signal methodology.

## ML Prediction (BQML / Vertex AI)

The **threshold-based** approach (`sql/correlation/`) uses per-county percentile thresholds for transparent, explainable risk scoring. The **ML-based** approach (`sql/ml/`) trains a regressor on weather features to predict outage severity (ratio 0.0–1.0) directly, with operational thresholds applied at prediction time. BQML boosted trees stay entirely in SQL; Vertex AI AutoML (documented in [docs/vertex-ai-guide.md](vertex-ai-guide.md), advanced/optional) provides maximum accuracy.

## Unit Conversions


| Variable      | WeatherNext Units        | Converted Units        | Formula           |
| ------------- | ------------------------ | ---------------------- | ----------------- |
| Wind speed    | m/s (u, v components)    | m/s (magnitude)        | `SQRT(u^2 + v^2)` |
| Precipitation | meters (6h accumulation) | millimeters            | `x 1000`          |
| Temperature   | Kelvin                   | Celsius                | `- 273.15`        |
| Wind speed    | m/s                      | mph (for US audiences) | `x 2.237`         |
| Wind speed    | m/s                      | knots (for aviation)   | `x 1.944`         |


