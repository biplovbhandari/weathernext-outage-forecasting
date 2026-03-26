#!/usr/bin/env python3
"""
WeatherNext Utility Forecasting — BigQuery SQL Pipeline Orchestrator.

Reads numbered SQL files from sql/{phase}/ subfolders, injects configuration
from config/.env by replacing DECLARE default values, and executes them
against BigQuery in order.

Usage:
    python pipeline.py                        # Run correlation + ml
    python pipeline.py --phase correlation    # Correlation only (weather → risk)
    python pipeline.py --phase ml             # ML only (training → model → evaluate)
    python pipeline.py --dry-run              # Print SQL, don't execute
"""

import argparse
import glob
import os
import re
import sys
import time

from google.cloud import bigquery
import config

SQL_BASE = os.path.join(os.path.dirname(__file__), '..', 'sql')

# Phases run in this order when --phase all is used
PHASE_ORDER = ['correlation', 'ml']

# Regex to match DECLARE lines by variable name
DECLARE_RE = re.compile(
    r"^(DECLARE\s+(\w+)\s+\S+\s+DEFAULT\s+)"  # DECLARE name type DEFAULT
    r"(.+?)"                                    # default value (non-greedy)
    r"(\s*;.*)$",                               # semicolon + optional comment
    re.MULTILINE
)


def build_replacement_map():
    """Build variable_name -> replacement_value mapping from config."""
    replacements = {
        'gcp_project':     f"'{config.GCP_PROJECT}'",
        'dataset_name':    f"'{config.DATASET_NAME}'",
        'weathernext_tbl': f"'{config.WEATHERNEXT_TABLE}'",
        'county_fips':     config.get_sql_fips_array(),
        'start_ts':        f"TIMESTAMP('{config.START_DATE} 00:00:00')",
        'end_ts':          f"TIMESTAMP('{config.END_DATE} 23:59:59')",
        'min_lead':        config.MIN_LEAD_HOURS,
        'max_lead':        config.MAX_LEAD_HOURS,
    }

    # Optional risk scoring / ML thresholds — only override if set in .env
    optional = {
        'wind_low':         config.WIND_THRESHOLD_LOW,
        'wind_high':        config.WIND_THRESHOLD_HIGH,
        'precip_low':       config.PRECIP_THRESHOLD_LOW,
        'precip_high':      config.PRECIP_THRESHOLD_HIGH,
        'w_wind':           config.WIND_WEIGHT,
        'w_precip':         config.PRECIP_WEIGHT,
        'outage_threshold': config.OUTAGE_THRESHOLD,
    }
    for name, value in optional.items():
        if value is not None:
            replacements[name] = value

    return replacements


def apply_variables(sql_content, replacements):
    """Replace DECLARE default values by matching on variable names."""
    def replace_match(m):
        var_name = m.group(2)
        if var_name in replacements:
            return m.group(1) + str(replacements[var_name]) + m.group(4)
        return m.group(0)

    return DECLARE_RE.sub(replace_match, sql_content)


def discover_sql_files(phase):
    """Discover SQL files for a phase, sorted by filename prefix number."""
    phase_dir = os.path.join(SQL_BASE, phase)
    if not os.path.isdir(phase_dir):
        print(f"Error: Phase directory not found: {phase_dir}")
        sys.exit(1)

    files = sorted(glob.glob(os.path.join(phase_dir, '*.sql')))
    if not files:
        print(f"Error: No SQL files found in {phase_dir}")
        sys.exit(1)

    return files


def execute_step(client, phase, filename, sql, dry_run, verbose):
    """Execute a single SQL step. Returns True on success."""
    print(f"\n{'='*60}")
    print(f"  [{phase}] {filename}")
    print(f"{'='*60}")

    if verbose or dry_run:
        print(sql)

    if dry_run:
        print(f"  [DRY RUN] Skipped execution")
        return True

    start_time = time.time()
    try:
        job = client.query(sql)
        job.result()
        elapsed = time.time() - start_time

        bytes_processed = job.total_bytes_processed or 0
        gb_processed = bytes_processed / (1024**3)
        print(f"  OK ({elapsed:.1f}s, {gb_processed:.3f} GB processed)")

        return True

    except Exception as e:
        elapsed = time.time() - start_time
        print(f"  FAILED ({elapsed:.1f}s)")
        print(f"  Error: {e}")
        return False


def print_summary(results):
    """Print execution summary."""
    print(f"\n{'='*60}")
    print(f"  Pipeline Summary")
    print(f"{'='*60}")

    for phase, filename, success in results:
        status = "OK" if success else "FAILED"
        print(f"  {status:6s}  [{phase}] {filename}")

    failed = [r for r in results if not r[2]]
    if failed:
        print(f"\n  {len(failed)} step(s) FAILED.")
        sys.exit(1)
    else:
        print(f"\n  All {len(results)} steps completed successfully.")


def parse_args():
    parser = argparse.ArgumentParser(
        description='WeatherNext Utility Forecasting — BigQuery SQL Pipeline',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Phases:\n"
            "  correlation  Weather extraction, join, risk scoring, preboard\n"
            "  ml           ML training data, model creation, evaluation\n"
            "  all          Run correlation then ml (default)\n"
            "\n"
            "Examples:\n"
            "  python pipeline.py                        # Run all phases\n"
            "  python pipeline.py --phase correlation    # Correlation only\n"
            "  python pipeline.py --phase ml             # ML only\n"
            "  python pipeline.py --dry-run              # Print SQL, don't execute\n"
            "  python pipeline.py --dry-run -v           # Print full SQL\n"
        )
    )
    parser.add_argument('--dry-run', action='store_true',
        help='Print parameterized SQL without executing')
    parser.add_argument('--phase', choices=['correlation', 'ml', 'all'],
        default='all',
        help='Pipeline phase to run (default: all)')
    parser.add_argument('--verbose', '-v', action='store_true',
        help='Print full SQL before execution')
    return parser.parse_args()


def main():
    args = parse_args()
    config.validate_config()

    # Determine which phases to run
    if args.phase == 'all':
        phases = PHASE_ORDER
    else:
        phases = [args.phase]

    replacements = build_replacement_map()

    print("WeatherNext Pipeline Orchestrator")
    print(f"  Project:  {config.GCP_PROJECT}")
    print(f"  Dataset:  {config.DATASET_NAME}")
    print(f"  Counties: {config.get_sql_fips_array()}")
    print(f"  Window:   {config.START_DATE} to {config.END_DATE}")
    print(f"  Leads:    {config.MIN_LEAD_HOURS}h to {config.MAX_LEAD_HOURS}h")
    print(f"  Phases:   {', '.join(phases)}")
    if args.dry_run:
        print(f"  Mode:     DRY RUN")

    # Initialize BigQuery client (skip in dry-run)
    client = None
    if not args.dry_run:
        try:
            client = bigquery.Client(project=config.GCP_PROJECT)
        except Exception as e:
            print(f"\nFailed to initialize BigQuery client: {e}")
            print("Ensure you are authenticated: gcloud auth application-default login")
            sys.exit(1)

    # Execute phases in order
    results = []
    for phase in phases:
        print(f"\n--- Phase: {phase} ---")
        sql_files = discover_sql_files(phase)

        for filepath in sql_files:
            filename = os.path.basename(filepath)

            with open(filepath) as f:
                sql = apply_variables(f.read(), replacements)

            success = execute_step(client, phase, filename, sql,
                                   args.dry_run, args.verbose)
            results.append((phase, filename, success))

            if not success:
                print_summary(results)
                return

    print_summary(results)


if __name__ == "__main__":
    main()
