import os

from google.cloud import bigquery
from google.cloud import storage

import config
from pipeline import apply_variables, resolve_format, discover_sql_files, build_replacement_map


def upload_to_gcs():
    print("=== Upload EAGLE-I data to GCS ===")
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


def load_eaglei_csv(client):
    print("\n=== Load EAGLE-I CSV from GCS ===")
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
    print("  Loaded data into eaglei_raw")


def run_setup_sql(client):
    replacements = build_replacement_map()
    sql_files = discover_sql_files('setup')

    for filepath in sql_files:
        filename = os.path.basename(filepath)
        print(f"\n=== {filename} ===")

        with open(filepath) as f:
            sql = apply_variables(f.read(), replacements)
        resolved = resolve_format(sql)
        client.query(resolved).result()
        print(f"  OK")

        # After eaglei_raw table is created, load the CSV data
        if '02_' in filename:
            load_eaglei_csv(client)


def main():
    print("Validating configuration for setup...")
    config.validate_config(is_setup=True)

    upload_to_gcs()
    client = bigquery.Client(project=config.GCP_PROJECT)
    run_setup_sql(client)

    print("\n=== Setup complete! ===")
    print("Next steps:")
    print("  1. Subscribe to WeatherNext Graph via Analytics Hub")
    print("  2. Run: python python/pipeline.py --phase correlation --dry-run")


if __name__ == "__main__":
    main()
