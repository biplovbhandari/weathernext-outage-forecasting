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
MIN_LEAD_HOURS = os.getenv("MIN_LEAD_HOURS", "24")
MAX_LEAD_HOURS = os.getenv("MAX_LEAD_HOURS", "48")
GCS_BUCKET = os.getenv("GCS_BUCKET")
GCS_BUCKET_LOCATION = os.getenv("GCS_BUCKET_LOCATION", "us-central1")
GCS_EAGLEI_CSV_PATH = os.getenv("GCS_EAGLEI_CSV_PATH", "")
LOCAL_EAGLEI_CSV_PATH = os.getenv("LOCAL_EAGLEI_CSV_PATH", "")

# Risk scoring thresholds (SQL files have sensible defaults)
WIND_THRESHOLD_LOW = os.getenv("WIND_THRESHOLD_LOW")
WIND_THRESHOLD_HIGH = os.getenv("WIND_THRESHOLD_HIGH")
PRECIP_THRESHOLD_LOW = os.getenv("PRECIP_THRESHOLD_LOW")
PRECIP_THRESHOLD_HIGH = os.getenv("PRECIP_THRESHOLD_HIGH")
WIND_WEIGHT = os.getenv("WIND_WEIGHT")
PRECIP_WEIGHT = os.getenv("PRECIP_WEIGHT")

# ML threshold (used by ml steps)
OUTAGE_THRESHOLD = os.getenv("OUTAGE_THRESHOLD")

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

def get_sql_fips_array() -> str:
    """Converts the comma-separated fips codes into a string representation of a SQL array."""
    if not COUNTY_FIPS:
        return "[]"
    fips_list = [f.strip() for f in COUNTY_FIPS.split(',')]
    fips_formatted = ", ".join([f"'{f}'" for f in fips_list])
    return f"[{fips_formatted}]"
