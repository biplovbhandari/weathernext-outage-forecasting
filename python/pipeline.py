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
    python pipeline.py --dry-run              # Print resolved SQL (pasteable into BQ Console)
    python pipeline.py --resume               # Skip steps whose target already exists
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
PHASE_ORDER = ['correlation', 'ml', 'looker']

# ML sub-phases map to (directory, file_prefix_glob)
ML_SUB_PHASES = {
    'ml-data':  ('ml', '01_*'),
    'ml-train': ('ml', '02_*'),
    'ml-eval':  ('ml', '03_*'),
}

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
        'end_ts':          f"TIMESTAMP('{config.END_DATE} 00:00:00')",
        'init_timestamps': config.get_sql_init_timestamps(),
        'lead_hours_arr':  config.get_sql_lead_hours_array(),
        'spatial_buffer_m': config.SPATIAL_BUFFER_M,
        'outage_threshold': config.OUTAGE_THRESHOLD,
        'event_out_thr':   config.EVENT_OUTAGE_THRESHOLD,
        'event_gap_min':   config.EVENT_GAP_MINUTES,
        'min_samples':     config.MIN_SAMPLES_PER_BLOCK,
        'hail_temp_thr':   config.HAIL_TEMP_THRESHOLD,
        'hail_precip_thr': config.HAIL_PRECIP_THRESHOLD,
        'wind_consist_min': config.WIND_CONSISTENCY_MIN,
        'hail_consist_min': config.HAIL_CONSISTENCY_MIN,
        'ml_max_iter':     config.ML_MAX_ITERATIONS,
        'ml_learn_rate':   config.ML_LEARN_RATE,
        'ml_child_weight': config.ML_MIN_TREE_CHILD_WEIGHT,
        'ml_subsample':    config.ML_SUBSAMPLE,
        'ml_budget_hrs':   config.ML_BUDGET_HOURS,
    }

    return replacements


def apply_variables(sql_content, replacements):
    """Replace DECLARE default values by matching on variable names."""
    def replace_match(m):
        var_name = m.group(2)
        if var_name in replacements:
            return m.group(1) + str(replacements[var_name]) + m.group(4)
        return m.group(0)

    return DECLARE_RE.sub(replace_match, sql_content)


def extract_declares(sql):
    """Extract DECLARE variable names and their default values from SQL."""
    declares = {}
    for m in DECLARE_RE.finditer(sql):
        var_name = m.group(2)
        raw_value = m.group(3).strip()
        declares[var_name] = raw_value
    return declares


def _find_runtime_declares(sql):
    """Find DECLARE lines without DEFAULT (runtime variables like target_aoi)."""
    return re.findall(r'^(DECLARE\s+\w+\s+\S+\s*;)\s*$', sql, re.MULTILINE)


def _resolve_placeholders(template, args, declares):
    """Replace FORMAT %s/%f placeholders with DECLARE values.

    Walks through args in order, matching each to the next %s or %f
    placeholder in the template. %s strips quotes (for identifiers),
    %f keeps the value as-is (for numerics).
    """
    resolved = template
    for arg in args:
        if arg not in declares:
            continue
        val = declares[arg]
        idx_s = resolved.find('%s')
        idx_f = resolved.find('%f')
        if idx_s >= 0 and (idx_f < 0 or idx_s < idx_f):
            resolved = resolved.replace('%s', val.strip("'"), 1)
        elif idx_f >= 0:
            resolved = resolved.replace('%f', val, 1)
    return resolved


def _resolve_using_params(resolved, using_str, declares):
    """Replace @param references from a USING clause.

    If the variable has a DECLARE default, substitute the literal value.
    If not (runtime variable like target_aoi), strip the @ prefix so it
    works as a plain script variable reference.
    """
    if not using_str:
        return resolved
    for pair in using_str.split(','):
        pair = pair.strip()
        parts = re.split(r'\s+AS\s+', pair, flags=re.IGNORECASE)
        if len(parts) == 2:
            var_name = parts[0].strip()
            alias = parts[1].strip().rstrip(';')
            if var_name in declares:
                resolved = resolved.replace(f'@{alias}', declares[var_name])
            else:
                resolved = resolved.replace(f'@{alias}', alias)
    return resolved


def _flatten_unnest(sql):
    """Convert IN UNNEST([...]) to flat IN (...) for partition pruning.

    BigQuery only prunes partitions on flat IN with literal values,
    not on IN UNNEST(array).
    """
    return re.sub(r'\bIN\s+UNNEST\(\[([^\]]+)\]\)', r'IN (\1)', sql)


# Regex to match EXECUTE IMMEDIATE FORMAT blocks (with optional INTO and USING)
_FORMAT_BLOCK_RE = re.compile(
    r'EXECUTE\s+IMMEDIATE\s+FORMAT\s*\(\s*"""'
    r'(.*?)'                                     # group 1: template body
    r'"""\s*,\s*'
    r'(.*?)'                                     # group 2: format args
    r'\)\s*'
    r'(?:INTO\s+(\w+)\s*)?'                      # group 3: optional INTO var_name
    r'(?:USING\s+(.*?)\s*)?'                     # group 4: optional USING clause
    r';',
    re.DOTALL
)


def resolve_format(sql):
    """Resolve EXECUTE IMMEDIATE FORMAT(...) into plain SQL.

    Handles multiple FORMAT blocks per file (e.g., step 01 has SET + CTAS).
    Returns plain SQL pasteable into BigQuery Console.
    """
    declares = extract_declares(sql)
    runtime_declares = _find_runtime_declares(sql)

    resolved_blocks = []
    for m in _FORMAT_BLOCK_RE.finditer(sql):
        args = [a.strip() for a in m.group(2).split(',') if a.strip()]
        resolved = _resolve_placeholders(m.group(1), args, declares)
        resolved = _resolve_using_params(resolved, m.group(4), declares)
        resolved = _flatten_unnest(resolved)

        if m.group(3):  # INTO var_name — produce SET statement
            resolved_blocks.append(f"SET {m.group(3)} = (\n{resolved.strip()}\n);")
        else:
            block = resolved.strip()
            if not block.endswith(';'):
                block += ';'
            resolved_blocks.append(block)

    if not resolved_blocks:
        # No FORMAT blocks — return SQL with DECLARE lines stripped
        return re.sub(r'^DECLARE\s+.*?;\s*\n', '', sql, flags=re.MULTILINE).strip()

    # Prepend runtime DECLARE lines (no DEFAULT) before resolved blocks
    return '\n\n'.join(runtime_declares + resolved_blocks)


def discover_sql_files(phase, file_filter=None):
    """Discover SQL files for a phase, sorted by filename prefix number.

    Args:
        phase: Directory name under sql/ (e.g., 'correlation', 'ml')
        file_filter: Optional glob pattern to filter files (e.g., '02_*')
    """
    phase_dir = os.path.join(SQL_BASE, phase)
    if not os.path.isdir(phase_dir):
        print(f"Error: Phase directory not found: {phase_dir}")
        sys.exit(1)

    pattern = file_filter + '.sql' if file_filter else '*.sql'
    files = sorted(glob.glob(os.path.join(phase_dir, pattern)))
    if not files:
        print(f"Error: No SQL files found in {phase_dir}/{pattern}")
        sys.exit(1)

    return files


def get_target_object(resolved_sql):
    """Extract target table/view/model name from resolved SQL."""
    match = re.search(
        r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|VIEW|MODEL|SCHEMA)'
        r'\s+(?:IF\s+NOT\s+EXISTS\s+)?`([^`]+)`',
        resolved_sql, re.IGNORECASE
    )
    return match.group(1) if match else None


def _detect_object_type(resolved_sql):
    """Detect if resolved SQL creates a TABLE, VIEW, MODEL, or SCHEMA."""
    match = re.search(
        r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|VIEW|MODEL|SCHEMA)',
        resolved_sql, re.IGNORECASE
    )
    if not match:
        return None
    token = match.group(0).upper()
    for t in ('VIEW', 'TABLE', 'MODEL', 'SCHEMA'):
        if t in token:
            return t
    return None


def object_exists(client, full_name, obj_type=None):
    """Check if a BigQuery table, view, or model exists."""
    try:
        if obj_type == 'MODEL':
            client.get_model(full_name)
        else:
            client.get_table(full_name)
        return True
    except Exception:
        return False


def execute_step(client, phase, filename, sql, dry_run, verbose, resume=False):
    """Execute a single SQL step. Returns True on success."""
    print(f"\n{'='*60}")
    print(f"  [{phase}] {filename}")
    print(f"{'='*60}")

    # Resolve EXECUTE IMMEDIATE FORMAT into plain SQL
    resolved_sql = resolve_format(sql)

    if resume and client:
        target = get_target_object(resolved_sql)
        obj_type = _detect_object_type(resolved_sql)
        if target and object_exists(client, target, obj_type):
            print(f"  SKIP (already exists: {target})")
            return True

    if dry_run or verbose:
        print(resolved_sql)

    if dry_run:
        # Detect object type and print cost guidance
        obj_type = _detect_object_type(resolved_sql)
        target = get_target_object(resolved_sql)
        target_name = target.split('.')[-1] if target else '?'
        if obj_type == 'VIEW':
            print(f"\n  [DRY RUN] {obj_type} ({target_name}) -- $0 to create")
        elif obj_type == 'SCHEMA':
            print(f"\n  [DRY RUN] {obj_type} ({target_name}) -- $0 to create")
        elif obj_type == 'MODEL':
            print(f"\n  [DRY RUN] {obj_type} ({target_name}) -- training may take minutes; consider running via BQ Console for visibility")
        elif obj_type == 'TABLE':
            print(f"\n  [DRY RUN] {obj_type} ({target_name}) -- paste SELECT into BQ Console to check cost")
        else:
            print(f"\n  [DRY RUN] Skipped execution")
        return True

    start_time = time.time()
    try:
        job = client.query(resolved_sql)
        obj_type = _detect_object_type(resolved_sql)

        if obj_type == 'MODEL':
            # MODEL training can take minutes — poll with progress updates
            print(f"  Training model (this may take several minutes)...")
            while not job.done():
                elapsed = time.time() - start_time
                print(f"  ... {elapsed:.0f}s elapsed", flush=True)
                time.sleep(10)
            job.result()  # raise if failed
        else:
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
            "  ml           ML training data, model creation, evaluation (all 3)\n"
            "  ml-data      ML step 1 only: prepare training data\n"
            "  ml-train     ML step 2 only: train model (may take minutes)\n"
            "  ml-eval      ML step 3 only: evaluate + predictions\n"
            "  looker       Dashboard views for Looker Studio / BI tools\n"
            "  all          Run correlation, ml, then looker (default)\n"
            "\n"
            "Examples:\n"
            "  python pipeline.py                        # Run all phases\n"
            "  python pipeline.py --phase correlation    # Correlation only\n"
            "  python pipeline.py --phase ml             # All ML steps\n"
            "  python pipeline.py --phase ml-train       # Train model only\n"
            "  python pipeline.py --phase ml-eval        # Evaluate only (model must exist)\n"
            "  python pipeline.py --dry-run              # Print resolved SQL (pasteable into BQ Console)\n"
            "  python pipeline.py --resume               # Skip completed steps\n"
        )
    )
    parser.add_argument('--dry-run', action='store_true',
        help='Print resolved plain SQL without executing (pasteable into BigQuery Console)')
    parser.add_argument('--phase',
        choices=['correlation', 'ml', 'ml-data', 'ml-train', 'ml-eval', 'looker', 'all'],
        default='all',
        help='Pipeline phase to run (default: all)')
    parser.add_argument('--verbose', '-v', action='store_true',
        help='Print full SQL before execution')
    parser.add_argument('--resume', action='store_true',
        help='Skip steps whose target table/view already exists in BigQuery')
    return parser.parse_args()


def main():
    args = parse_args()
    config.validate_config()

    # Determine which phases to run: list of (dir_name, file_filter) tuples
    if args.phase in ML_SUB_PHASES:
        dir_name, file_filter = ML_SUB_PHASES[args.phase]
        phase_list = [(dir_name, file_filter)]
    elif args.phase == 'all':
        phase_list = [(p, None) for p in PHASE_ORDER]
    else:
        phase_list = [(args.phase, None)]

    replacements = build_replacement_map()

    print("WeatherNext Pipeline Orchestrator")
    print(f"  Project:  {config.GCP_PROJECT}")
    print(f"  Dataset:  {config.DATASET_NAME}")
    print(f"  Counties: {config.get_sql_fips_array()}")
    print(f"  Window:   {config.START_DATE} to {config.END_DATE}")
    print(f"  Leads:    {config.LEAD_HOURS}")
    print(f"  Init hrs: {config.INIT_HOURS} (UTC)")
    print(f"  Phases:   {args.phase}")
    if args.dry_run:
        print(f"  Mode:     DRY RUN")
    if args.resume:
        print(f"  Mode:     RESUME (skip existing)")

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
    for phase, file_filter in phase_list:
        print(f"\n--- Phase: {phase}{f' ({file_filter})' if file_filter else ''} ---")
        sql_files = discover_sql_files(phase, file_filter)

        for filepath in sql_files:
            filename = os.path.basename(filepath)

            with open(filepath) as f:
                sql = apply_variables(f.read(), replacements)

            success = execute_step(client, phase, filename, sql,
                                   args.dry_run, args.verbose,
                                   resume=args.resume)
            results.append((phase, filename, success))

            if not success:
                print_summary(results)
                return

    print_summary(results)


if __name__ == "__main__":
    main()
