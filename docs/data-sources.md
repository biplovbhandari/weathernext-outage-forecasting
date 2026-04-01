# Data Sources

## EAGLE-I Outage Data

### What It Is

EAGLE-I (Environment for Analysis of Geo-Located Energy Information) is maintained by the US Department of Energy's Office of Electricity. It aggregates outage reports from utilities across the United States.

### How to Obtain

1. Visit [eagle-i.doe.gov](https://eagle-i.doe.gov/)
2. Navigate to the data download section
3. Download county-level outage data for your desired date range
4. The CSV should contain: fips_code, county, state, customers_out, run_start_time, total_customers

### Data Format

| Field | Type | Description |
|-------|------|-------------|
| fips_code | Integer | 5-digit county FIPS (may be stored as integer without leading zeros) |
| county | String | County name |
| state | String | State name |
| customers_out | Integer | Number of customers without power |
| run_start_time | Timestamp | Observation time (UTC) |
| total_customers | Integer | Total customers served in county |

### Temporal Resolution

Reports arrive at 15-minute intervals. Gaps may exist due to utility reporting delays or technical issues. The pipeline handles gaps gracefully — missing intervals simply produce no rows for that period.

### Data Quality Notes

- Some utilities report inconsistently; `total_customers` may change slightly between reports
- `customers_out = 0` is a valid report (no outage); NULL means no report received
- FIPS codes are integers in the raw data; we LPAD to 5 digits for consistent joining

## WeatherNext Graph Forecasts

### What It Is

WeatherNext Graph is Google DeepMind's deterministic AI weather model, made available through BigQuery Analytics Hub. It produces global 10-day forecasts at ~0.25° resolution.

### How to Subscribe

1. Go to [BigQuery Analytics Hub](https://console.cloud.google.com/bigquery/analytics-hub) in the Google Cloud Console
2. Search for "WeatherNext" in the Analytics Hub Explorer
3. Subscribe to the **WeatherNext Graph** listing
4. Choose your destination project and dataset name
5. The listing creates a linked dataset — no data is copied

After subscribing, note the full table path (e.g., `your-project.weathernext_graph_forecasts.59572747_4_0`). You'll need this for your `config/.env`.

### Pricing

Analytics Hub subscription fees are set by the data publisher (Google). Check the listing page for current pricing. BigQuery scan costs (for your queries) are separate and depend on your usage.

### Table Schema

See [concepts.md](concepts.md) for the detailed schema. The key thing to know: the `forecast` field is a deeply nested ARRAY<STRUCT> containing all variables at all forecast steps. Always use column pruning when querying.

### Available Initialization Times

WeatherNext runs multiple times daily. Each `init_time` represents when the forecast was generated. For this project, we use only the 00Z (midnight UTC) run to control costs.

## US County Boundaries

### What It Is

County boundary polygons from the US Census Bureau, hosted as a free BigQuery public dataset.

### Access

No subscription needed. Query directly:

```sql
SELECT * FROM `bigquery-public-data.geo_us_boundaries.counties` LIMIT 10;
SELECT * FROM `bigquery-public-data.geo_us_boundaries.states` LIMIT 10;
```

### Important Note

These tables are in the **US multi-region** location. Your working dataset must also be in US multi-region (not a regional location like `us-central1`) to join with them.

## Optional: FEMA Flood Claims

The conversations referenced `openfema.fima_nfip_redacted_claims` as a potential additional data source for flood-related outage analysis. This is available as a BigQuery public dataset but is not used in the current pipeline.
