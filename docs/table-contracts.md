# Table Contracts

Every shared table and view in the pipeline, which phase produces it, and which phases consume it. This is the reference for understanding what breaks downstream when you modify a step.

## Dependency Map

### Setup Phase Outputs

| Object | Type | Produced By | Consumed By |
|---|---|---|---|
| `eaglei_raw` | TABLE | `setup/02` | `setup/03` |
| `eaglei_part` | TABLE | `setup/03` | `correlation/02`, `correlation/06` |
| `counties_ref` | TABLE | `setup/04` | `correlation/01`, `correlation/03`, `looker/01` |

### Correlation Phase Outputs

| Object | Type | Produced By | Consumed By |
|---|---|---|---|
| `graph_multi_ingredients_hourly` | TABLE | `correlation/01` | `correlation/04`, `correlation/05`, `correlation/07`, `correlation/08` |
| `view_eaglei_6h_qc` | VIEW | `correlation/02` | `correlation/05` |
| `view_six_hour_grid` | VIEW | `correlation/03` | `correlation/05` |
| `view_windhail_thresholds` | VIEW | `correlation/04` | `correlation/07`, `correlation/08`, `correlation/09` |
| `view_outage_vs_wx_6h_qc` | VIEW | `correlation/05` | `correlation/09`, `correlation/10`, `ml/01`, `looker/01` |
| `events_restoration` | TABLE | `correlation/06` | `correlation/07` |
| `event_coverage_wx` | TABLE | `correlation/07` | `looker/01` |
| `view_daily_plan` | VIEW | `correlation/08` | `looker/01` |
| `lead_performance` | TABLE | `correlation/09` | (end consumer) |
| `correlations` | TABLE | `correlation/10` | `looker/01` |

### ML Phase Outputs

Which models are trained is controlled by `ML_MODELS` in `config/.env`. Each model produces its own set of output tables with a `_{model_key}` suffix. The table below shows outputs for all 4 model types.

**Shared:**

| Object | Type | Produced By | Consumed By |
|---|---|---|---|
| `bqml_training_data` | TABLE | `ml/01` | `ml/02a-d`, `ml/03` |

**Per model** (created for each model in `ML_MODELS`):

| Object pattern | Type | Produced By | Notes |
|---|---|---|---|
| `outage_predictor_{key}` | MODEL | `ml/02a-d` | One per model (regressor, classifier, logistic, automl) |
| `bqml_evaluation_{key}` | TABLE | `ml/03` | Regression metrics (regressor) or classifier metrics (others) |
| `bqml_feature_importance_{key}` | TABLE | `ml/03` | Feature importance via ML.GLOBAL_EXPLAIN |
| `bqml_predictions_{key}` | TABLE | `ml/03` | Predicted ratio (regressor) or probability (classifiers) + tier |
| `bqml_threshold_sweep_{key}` | TABLE | `ml/03` | Regressor only: precision/recall/F1 at cutoffs |
| `bqml_confusion_matrix_{key}` | TABLE | `ml/03` | Classifiers only: TP/FP/FN/TN |
| `bqml_roc_curve_{key}` | TABLE | `ml/03` | Classifiers only: ROC curve data |

### Looker Phase Outputs

| Object | Type | Produced By | Consumed By |
|---|---|---|---|
| `looker_timeseries_6h` | VIEW | `looker/01` | (end consumer) |
| `looker_correlation` | VIEW | `looker/01` | (end consumer) |
| `looker_risk_map` | VIEW | `looker/01` | (end consumer) |
| `looker_preboard` | VIEW | `looker/01` | (end consumer) |
| `looker_events` | VIEW | `looker/01` | (end consumer) |

---

## Column Schemas

### graph_multi_ingredients_hourly

The primary weather feature table. Most expensive query to produce. All downstream analysis reads from this.
Partitioned by `DATE(hour_ts)`, clustered by `(county_fips, lead_hours)`.

| Column | Type | Description |
|--------|------|-------------|
| county_fips | STRING | 5-digit FIPS code (aliased from county_fips_code) |
| county_name | STRING | County display name |
| hour_ts | TIMESTAMP | 6-hour block start (00/06/12/18 UTC) |
| lead_hours | INT64 | Forecast lead time in hours |
| ws10_max_mps | FLOAT64 | Max 10m wind speed (m/s) across grid cells in county |
| ws925_max_mps | FLOAT64 | Max 925hPa wind speed (m/s) |
| shear_0_6km_max_mps | FLOAT64 | Max 0-6km wind shear (m/s) |
| updraft700_pos_max_pas | FLOAT64 | Max positive 700hPa vertical velocity (Pa/s) |
| t700_c_min | FLOAT64 | Min 700hPa temperature (°C) |
| t700_c_mean | FLOAT64 | Mean 700hPa temperature (°C) |
| t850_c_mean | FLOAT64 | Mean 850hPa temperature (°C) |
| tp6_mm_max | FLOAT64 | Max 6-hour total precipitation (mm) |
| tp6_mm_mean | FLOAT64 | Mean 6-hour total precipitation (mm) |

### view_outage_vs_wx_6h_qc

The master join view. Base for all downstream analysis — weather + outages + QC on the 6-hour grid scaffold.

| Column | Type | Description |
|--------|------|-------------|
| county_fips | STRING | 5-digit FIPS code |
| valid_ts | TIMESTAMP | 6-hour block timestamp (from grid scaffold) |
| lead_hours | INT64 | Forecast lead time in hours |
| ws10_max_mps | FLOAT64 | Max 10m wind speed (m/s) |
| ws925_max_mps | FLOAT64 | Max 925hPa wind speed (m/s) |
| shear_0_6km_max_mps | FLOAT64 | Max 0-6km wind shear (m/s) |
| updraft700_pos_max_pas | FLOAT64 | Max positive 700hPa vertical velocity (Pa/s) |
| t700_c_min | FLOAT64 | Min 700hPa temperature (°C) |
| t700_c_mean | FLOAT64 | Mean 700hPa temperature (°C) |
| t850_c_mean | FLOAT64 | Mean 850hPa temperature (°C) |
| tp6_mm_mean | FLOAT64 | Mean 6-hour total precipitation (mm) |
| tp6_mm_max | FLOAT64 | Max 6-hour total precipitation (mm) |
| hail_flag | INT64 | 1 if t700_c_min <= threshold AND tp6_mm_max >= threshold |
| outage_ratio_6h_max | FLOAT64 | Max outage ratio during 6h block |
| outage_ratio_6h_mean | FLOAT64 | Mean outage ratio during 6h block |
| samples_in_block | INT64 | Number of EAGLE-I 15-min samples in the block |
| customers_out_6h_max | INT64 | Max customers out during 6h block |

### bqml_training_data

ML training features + labels derived from the master view.

| Column | Type | Description |
|--------|------|-------------|
| county_fips | STRING | 5-digit FIPS code |
| valid_ts | TIMESTAMP | 6-hour block timestamp |
| ws10_max_mps | FLOAT64 | 10m wind speed max (m/s) |
| ws925_max_mps | FLOAT64 | 925hPa wind speed max (m/s) |
| shear_0_6km_max_mps | FLOAT64 | 0-6km wind shear max (m/s) |
| updraft700_pos_max_pas | FLOAT64 | 700hPa updraft max (Pa/s) |
| tp6_mm_max | FLOAT64 | 6h precipitation max (mm) |
| t700_c_min | FLOAT64 | 700hPa temperature min (°C) |
| t850_c_mean | FLOAT64 | 850hPa temperature mean (°C) |
| hail_flag | INT64 | Binary hail indicator |
| lead_hours | INT64 | Forecast lead time in hours |
| hour_of_day | INT64 | Hour of day from valid_ts (0-23) |
| day_of_week | INT64 | Day of week from valid_ts (1=Sun, 7=Sat) |
| month | INT64 | Month from valid_ts (1-12) |
| wind_precip_interaction | FLOAT64 | Derived: ws10_max_mps * tp6_mm_max |
| wind_squared | FLOAT64 | Derived: ws10_max_mps^2 |
| shear_updraft_interaction | FLOAT64 | Derived: shear * updraft |
| outage_ratio_6h_max | FLOAT64 | Raw outage ratio (regression label) |
| outage_event | INT64 | Binary label: 1 if outage_ratio >= OUTAGE_THRESHOLD |
| data_split | STRING | 'TRAIN' (80%) or 'TEST' (20%), deterministic by county + date |
