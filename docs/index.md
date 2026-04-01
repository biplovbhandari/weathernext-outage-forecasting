# WeatherNext Outage Forecasting

**Predict power outages 24-48 hours in advance using Google DeepMind's WeatherNext AI weather forecasts.**

This project correlates [WeatherNext](https://deepmind.google/discover/blog/graphcast-ai-model-for-faster-and-more-accurate-global-weather-forecasting/) AI weather forecasts with [EAGLE-I](https://eagle-i.doe.gov/) power outage data on Google Cloud BigQuery to help electric utilities pre-position repair crews ahead of severe weather events.

---

## What This Project Does

1. **Extracts** multi-ingredient weather features (wind, shear, hail proxy, precipitation, temperature) at multiple lead times (24-48h)
2. **Detects** outage events and evaluates which forecasts detected them
3. **Scores risk** per county using data-driven thresholds (p90 wind, p80 updraft)
4. **Trains ML models** (BQML regression) to predict outage severity
5. **Pre-positions crews** 24-48 hours before a storm hits

## Quick Start

See the [project README on GitHub](https://github.com/biplovbhandari/weathernext-outage-forecasting) for setup instructions.

## Documentation

- [Architecture](architecture.md) — System design, data flow, configuration reference
- [Concepts](concepts.md) — Weather variables, outage cadence, thresholds, ML approach
- [Data Sources](data-sources.md) — EAGLE-I, WeatherNext Graph, US county boundaries
- [Cost Estimates](cost-estimates.md) — BigQuery pricing, optimization strategies
- [Looker Studio](looker-studio-guide.md) — Dashboard setup and view mapping
- [Vertex AI](vertex-ai-guide.md) — Advanced: standalone AutoML alternative to BQML
