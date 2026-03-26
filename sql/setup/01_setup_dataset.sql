-- ============================================================================
-- WeatherNext Utility Forecasting — Dataset Setup (Parameterized)
-- ============================================================================
-- Configure these variables for your GCP environment.
-- All subsequent SQL files reference the same variable names.
-- ============================================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │  CONFIGURATION — Edit these for your environment        │
-- └─────────────────────────────────────────────────────────┘
DECLARE gcp_project   STRING DEFAULT 'YOUR_GCP_PROJECT';
DECLARE dataset_name  STRING DEFAULT 'weathernext_demo';

-- Create dataset in US multi-region (required for public data joins)
EXECUTE IMMEDIATE FORMAT("""
  CREATE SCHEMA IF NOT EXISTS `%s.%s`
  OPTIONS (
    location = 'US',
    description = 'WeatherNext + EAGLE-I outage forecasting'
  )
""", gcp_project, dataset_name);
