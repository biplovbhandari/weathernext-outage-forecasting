import os
from google.cloud import bigquery
from google.cloud import storage
import config


def upload_to_gcs():
    print("=== Step 1: Upload EAGLE-I data to GCS ===")
    storage_client = storage.Client(project=config.GCP_PROJECT)
    bucket = storage_client.bucket(config.GCS_BUCKET)

    if not bucket.exists():
        print(f"Bucket gs://{config.GCS_BUCKET} does not exist. Creating it in {config.GCS_BUCKET_LOCATION}...")
        bucket.create(location=config.GCS_BUCKET_LOCATION)
        print(f"Bucket created successfully.")

    # ensure local file exists
    local_path = os.path.join(os.path.dirname(__file__), '..', config.LOCAL_EAGLEI_CSV_PATH)
    if not os.path.exists(local_path):
        print(f"Warning: Expected local data file at {local_path} but it was not found.")
        print("Please ensure you have downloaded the data and placed it there before running.")
        return

    blob = bucket.blob(config.GCS_EAGLEI_CSV_PATH)
    blob.upload_from_filename(local_path)
    print(f"Uploaded {local_path} to gs://{config.GCS_BUCKET}/{config.GCS_EAGLEI_CSV_PATH}")


def create_dataset():
    print("\n=== Step 2: Create BigQuery dataset ===")
    client = bigquery.Client(project=config.GCP_PROJECT)
    dataset_id = f"{config.GCP_PROJECT}.{config.DATASET_NAME}"

    dataset = bigquery.Dataset(dataset_id)
    dataset.location = "US"
    dataset.description = "WeatherNext + EAGLE-I outage forecasting"
    try:
        client.create_dataset(dataset, exists_ok=True)
        print(f"Created/verified dataset {dataset_id}")
    except Exception as e:
        print(f"Dataset creation constraint: {e}")

    return client


def run_setup_queries(client):
    dataset_prefix = f"`{config.GCP_PROJECT}.{config.DATASET_NAME}`"

    print("\n=== Step 3: Create raw EAGLE-I table ===")
    q1 = f"""
    CREATE TABLE IF NOT EXISTS {dataset_prefix}.eaglei_raw (
      fips_code       INT64,
      county          STRING,
      state           STRING,
      customers_out   INT64,
      run_start_time  TIMESTAMP,
      total_customers INT64
    );
    """
    client.query(q1).result()

    print("\n=== Step 4: Load EAGLE-I CSV from GCS ===")
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,
        field_delimiter=","
    )
    uri = f"gs://{config.GCS_BUCKET}/{config.GCS_EAGLEI_CSV_PATH}"
    table_id = f"{config.GCP_PROJECT}.{config.DATASET_NAME}.eaglei_raw"
    load_job = client.load_table_from_uri(uri, table_id, job_config=job_config)
    load_job.result()
    print("Loaded data into eaglei_raw")

    print("\n=== Step 5: Create partitioned outage table ===")
    q2 = f"""
    CREATE OR REPLACE TABLE {dataset_prefix}.eaglei_part
    PARTITION BY DATE(ts)
    CLUSTER BY county_fips
    AS
    SELECT
      LPAD(CAST(fips_code AS STRING), 5, '0')                AS county_fips,
      county,
      state,
      customers_out,
      total_customers,
      SAFE_DIVIDE(customers_out, NULLIF(total_customers, 0))  AS outage_ratio,
      TIMESTAMP(run_start_time)                               AS ts
    FROM {dataset_prefix}.eaglei_raw;
    """
    client.query(q2).result()

    print("\n=== Step 6: Create counties reference table ===")
    q3 = f"""
    CREATE OR REPLACE TABLE {dataset_prefix}.counties_ref AS
    SELECT
      c.county_fips_code,
      c.state_fips_code,
      s.state_name,
      c.county_name,
      c.county_geom
    FROM `bigquery-public-data.geo_us_boundaries.counties` c
    LEFT JOIN `bigquery-public-data.geo_us_boundaries.states` s
      USING (state_fips_code);
    """
    client.query(q3).result()

    print("\n=== Step 7: Create hourly outage view ===")
    q4 = f"""
    CREATE OR REPLACE VIEW {dataset_prefix}.view_eaglei_hourly AS
    WITH hourly AS (
      SELECT
        county_fips,
        TIMESTAMP_TRUNC(ts, HOUR) AS hour_ts,
        AVG(outage_ratio)         AS outage_ratio_hour
      FROM {dataset_prefix}.eaglei_part
      GROUP BY county_fips, hour_ts
    )
    SELECT
      h.county_fips,
      h.hour_ts,
      h.outage_ratio_hour,
      c.state_name,
      c.county_name,
      c.county_geom AS geom
    FROM hourly h
    JOIN {dataset_prefix}.counties_ref c
      ON h.county_fips = c.county_fips_code;
    """
    client.query(q4).result()


def main():
    print("Validating configuration for setup...")
    config.validate_config(is_setup=True)

    upload_to_gcs()
    client = create_dataset()
    run_setup_queries(client)

    print("\n=== Setup complete! ===")
    print("Next steps:")
    print("  1. Subscribe to WeatherNext Graph via Analytics Hub")
    print("  2. Run: python python/pipeline.py")


if __name__ == "__main__":
    main()
