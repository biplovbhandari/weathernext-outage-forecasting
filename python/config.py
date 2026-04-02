import os
from dotenv import load_dotenv

# Load environment variables from config/.env
env_path = os.path.join(os.path.dirname(__file__), '..', 'config', '.env')
load_dotenv(dotenv_path=env_path)

GCP_PROJECT = os.getenv("GCP_PROJECT")
DATASET_NAME = os.getenv("DATASET_NAME")
WEATHERNEXT_TABLE = os.getenv("WEATHERNEXT_TABLE")
COUNTY_FIPS = os.getenv("COUNTY_FIPS")
START_DATE = os.getenv("START_DATE")
END_DATE = os.getenv("END_DATE")
LEAD_HOURS = os.getenv("LEAD_HOURS", "24,30,36,42,48")
INIT_HOURS = os.getenv("INIT_HOURS", "0")
GCS_BUCKET = os.getenv("GCS_BUCKET")
GCS_BUCKET_LOCATION = os.getenv("GCS_BUCKET_LOCATION", "us-central1")
GCS_EAGLEI_CSV_PATH = os.getenv("GCS_EAGLEI_CSV_PATH", "")
LOCAL_EAGLEI_CSV_PATH = os.getenv("LOCAL_EAGLEI_CSV_PATH", "")
SPATIAL_BUFFER_M = os.getenv("SPATIAL_BUFFER_M", "25000")

# ML threshold
OUTAGE_THRESHOLD = os.getenv("OUTAGE_THRESHOLD", "0.05")

# Event detection
EVENT_OUTAGE_THRESHOLD = os.getenv("EVENT_OUTAGE_THRESHOLD", "0.005")
EVENT_GAP_MINUTES = os.getenv("EVENT_GAP_MINUTES", "60")

# QC
MIN_SAMPLES_PER_BLOCK = os.getenv("MIN_SAMPLES_PER_BLOCK", "8")

# BQML hyperparameters
ML_MAX_ITERATIONS = os.getenv("ML_MAX_ITERATIONS", "50")
ML_LEARN_RATE = os.getenv("ML_LEARN_RATE", "0.1")
ML_MIN_TREE_CHILD_WEIGHT = os.getenv("ML_MIN_TREE_CHILD_WEIGHT", "5")
ML_SUBSAMPLE = os.getenv("ML_SUBSAMPLE", "0.8")
ML_BUDGET_HOURS = os.getenv("ML_BUDGET_HOURS", "1.0")

# Hail detection
HAIL_TEMP_THRESHOLD = os.getenv("HAIL_TEMP_THRESHOLD", "0.0")
HAIL_PRECIP_THRESHOLD = os.getenv("HAIL_PRECIP_THRESHOLD", "2.0")

# Daily plan consistency
WIND_CONSISTENCY_MIN = os.getenv("WIND_CONSISTENCY_MIN", "2")
HAIL_CONSISTENCY_MIN = os.getenv("HAIL_CONSISTENCY_MIN", "1")


def validate_config(is_setup=False):
    """Validates that all required configuration variables are present."""
    missing = []
    required_vars = [
        "GCP_PROJECT",
        "DATASET_NAME",
        "WEATHERNEXT_TABLE",
        "COUNTY_FIPS",
        "START_DATE",
        "END_DATE"
    ]
    if is_setup:
        required_vars.extend(["GCS_BUCKET"])

    for var_name in required_vars:
        if not globals().get(var_name):
            missing.append(var_name)

    if missing:
        raise ValueError(f"Missing required environment variables in config/.env: {', '.join(missing)}")


def get_sql_init_timestamps() -> str:
    """Generate explicit init_time timestamps for partition pruning.

    Produces a SQL TIMESTAMP array with one entry per (date, init_hour) combination
    covering the full date range needed for the configured lead window.
    """
    from datetime import datetime, timedelta

    start = datetime.strptime(START_DATE, '%Y-%m-%d')
    end = datetime.strptime(END_DATE, '%Y-%m-%d')
    max_lead = max(int(h.strip()) for h in LEAD_HOURS.split(','))
    hours = [int(h.strip()) for h in INIT_HOURS.split(',')]

    # Earliest init_time: a forecast made max_lead hours before start could
    # have valid times within the window
    earliest = start - timedelta(hours=max_lead)
    earliest_date = earliest.replace(hour=0, minute=0, second=0)

    timestamps = []
    d = earliest_date
    while d <= end:
        for h in hours:
            ts = d.replace(hour=h, minute=0, second=0)
            timestamps.append(f"TIMESTAMP('{ts.strftime('%Y-%m-%d %H:%M:%S')}')")
        d += timedelta(days=1)

    return f"[{', '.join(timestamps)}]"


def get_sql_fips_array() -> str:
    """Converts the comma-separated fips codes into a string representation of a SQL array."""
    if not COUNTY_FIPS:
        return "[]"
    fips_list = [f.strip() for f in COUNTY_FIPS.split(',')]
    fips_formatted = ", ".join([f"'{f}'" for f in fips_list])
    return f"[{fips_formatted}]"


def get_sql_lead_hours_array() -> str:
    """Converts comma-separated lead hours to SQL INT64 array: [24, 30, 36, 42, 48]."""
    hours = [h.strip() for h in LEAD_HOURS.split(',')]
    return f"[{', '.join(hours)}]"
