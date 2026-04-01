# GCP Cost Estimates

## IMPORTANT: Always Verify Before Running

**Step 01 (WeatherNext extraction) is the main cost driver.** All other steps scan < 1 GB and cost negligibly.

```bash
# 1. Generate resolved SQL (pasteable into BigQuery Console)
python python/pipeline.py --phase correlation --dry-run

# 2. Copy step 01's output into BigQuery Console
#    The estimated bytes will appear in the top-right corner

# 3. Or use bq CLI
bq query --use_legacy_sql=false --dry_run "PASTE_RESOLVED_SQL_HERE"
```

The `--dry-run` output labels each step as TABLE or VIEW. VIEWs cost $0 to create. Only TABLE steps need cost verification.

## Pricing Model

BigQuery charges $6.25 per TB scanned (on-demand pricing -- verify current rates at [cloud.google.com/bigquery/pricing](https://cloud.google.com/bigquery/pricing)). Storage is $0.02/GB/month for active tables. Looker Studio is free for the first 10 users.

## Cost by Step Type

| Step Type | Typical Scan | Cost | Notes |
|-----------|-------------|------|-------|
| Step 01: WeatherNext extraction (TABLE) | Varies widely | Verify with --dry-run | Depends on cluster/partition pruning effectiveness |
| Steps 02-05: Views (VIEW) | 0 bytes | $0 | Views don't scan data at creation time |
| Steps 06-07: Event detection (TABLE) | < 500 MB | < $0.01 | Reads from small eaglei_part table |
| Steps 08: Daily plan (VIEW) | 0 bytes | $0 | View creation is free |
| Steps 09-10: Lead performance + correlations (TABLE) | < 1 GB | < $0.01 | Reads from materialized step 01 output |
| ML phase: All 3 steps | < 2 GB | < $0.02 | Reads from small materialized tables |
| Looker views: 5 views | 0 bytes | $0 | View creation is free |

## Cost Optimization Strategies

### 1. Cluster Pruning via Pre-computed AOI (Most Impactful)

The WeatherNext table is clustered by `geography`. Step 01 pre-computes an AOI geometry from your target counties (with spatial buffer), stores it as a DECLARE variable, then uses `ST_INTERSECTS(t.geography, target_aoi)` to leverage the cluster index. This is the single most impactful optimization -- it reduces the scan from the full global grid (~1M points) to just the grid cells near your counties.

### 2. Partition Pruning via Explicit Timestamps

The WeatherNext table is partitioned by `init_time`. Pipeline.py generates explicit init timestamps (one per day per init hour) and uses `t.init_time IN (TIMESTAMP('...'), ...)` with literal values. BigQuery can prune partitions on literal IN clauses.

**Warning:** `EXTRACT()` and `IN UNNEST(array_variable)` do NOT enable partition pruning. Only literal comparisons and literal IN lists work.

### 3. Column Pruning on UNNEST

The `forecast` array contains ~89 bands. Selecting all of them (`SELECT *`) scans the entire nested structure. By selecting only the ~6 fields needed, we reduce per-row scan by ~93%.

### 4. Init Time Filtering

WeatherNext runs 4 times daily (00Z, 06Z, 12Z, 18Z). Default config uses only 00Z (`INIT_HOURS=0`), reducing partition count by ~75%. Configure `INIT_HOURS=0,12` if you need both morning and afternoon forecasts.

### 5. Materialization

Step 01 materializes extracted features into a table. All downstream steps (02-10) read this small table instead of re-scanning WeatherNext. This is why steps 02-10 are cheap even if they're re-run multiple times.

## Free Tier Considerations

BigQuery's free tier includes 1 TB of query processing per month. Whether the demo fits within the free tier depends on how effectively cluster and partition pruning reduce the WeatherNext scan. Always verify with `--dry-run`.

## What's NOT Included

- Analytics Hub subscription fees for WeatherNext (check with Google for current pricing)
- Cloud Storage costs for EAGLE-I CSV files (typically negligible)
- Looker Studio Pro licensing (if needed for > 10 users or advanced features)
- Compute costs for any future Cloud Functions / Cloud Run automation
