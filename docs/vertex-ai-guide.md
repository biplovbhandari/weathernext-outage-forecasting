# Vertex AI AutoML Guide (Advanced / Optional) (Needs Testing)

> **This guide is optional.** The main pipeline uses BQML (BigQuery ML) with a regression model for all ML tasks — no additional services required. This Vertex AI path is for advanced users who want Google's fully managed AutoML platform.
>
> **Note:** The main BQML pipeline uses a **regressor** (predicts `outage_ratio_6h_max`, a continuous 0.0–1.0 value). This Vertex AI guide demonstrates the **classification** approach (binary `outage_event`) as an alternative. Both targets are available in `bqml_training_data`.

This guide covers training an outage prediction model using Vertex AI AutoML Tables as an alternative to BigQuery ML.

## When to Use Vertex AI vs BQML

Use **BQML** (the default in this repo) when you want everything in SQL with no additional infrastructure. BQML boosted trees perform well and the entire workflow stays inside BigQuery.

Use **Vertex AI AutoML** when you want Google's fully managed model search, which tries hundreds of architectures and hyperparameter combinations. It typically produces the best performance but costs more and requires additional GCP setup.

## Prerequisites

- Vertex AI API enabled in your GCP project
- BigQuery dataset with training data already built (run correlation + `--phase ml-data`)
- Service account with roles: `roles/aiplatform.user`, `roles/bigquery.dataViewer`

## Step 1: Export Training Data

The BQML training table (`bqml_training_data`) works directly as a Vertex AI data source. No export needed — Vertex AI can read from BigQuery.

The table contains both target columns:

- `outage_ratio_6h_max` — for regression (continuous 0.0–1.0)
- `outage_event` — for classification (binary 0/1)

## Step 2: Create Dataset in Vertex AI

```bash
# Using gcloud CLI
gcloud ai datasets create \
  --display-name="outage-prediction-training" \
  --metadata-schema-uri=gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml \
  --project=$GCP_PROJECT \
  --region=us-central1
```

Then import from BigQuery:

```bash
gcloud ai datasets import $DATASET_ID \
  --source=bq://$GCP_PROJECT.$DATASET_NAME.bqml_training_data \
  --import-schema-uri=gs://google-cloud-aiplatform/schema/dataset/ioformat/tabular_io_format_1.0.0.yaml
```

## Step 3: Train AutoML Model

For **classification** (binary outage yes/no):

```bash
gcloud ai models create \
  --display-name="outage-predictor-automl-classifier" \
  --dataset=$DATASET_ID \
  --target-column=outage_event \
  --training-budget-milli-node-hours=1000 \
  --model-type=CLOUD \
  --predefined-split-column-name=data_split \
  --project=$GCP_PROJECT \
  --region=us-central1
```

For **regression** (continuous outage severity):

```bash
gcloud ai models create \
  --display-name="outage-predictor-automl-regressor" \
  --dataset=$DATASET_ID \
  --target-column=outage_ratio_6h_max \
  --training-budget-milli-node-hours=1000 \
  --model-type=CLOUD \
  --predefined-split-column-name=data_split \
  --project=$GCP_PROJECT \
  --region=us-central1
```

Alternatively, use the Console UI:

1. Go to **Vertex AI → Training** in the Cloud Console
2. Click **Create** and select **AutoML**
3. Choose the BigQuery table as your data source
4. Set target column: `outage_event` (classification) or `outage_ratio_6h_max` (regression)
5. Set `data_split` as the predefined split column
6. Set budget to 1 node-hour (sufficient for this dataset size)
7. Click **Start Training**

Training typically takes 1–3 hours.

## Step 4: Evaluate the Model

In the Console, navigate to the trained model and view the **Evaluate** tab.

**For classification** — key metrics:


| Metric    | Target |
| --------- | ------ |
| Precision | ≥ 0.65 |
| Recall    | ≥ 0.85 |
| F1        | ≥ 0.75 |
| AUC-ROC   | ≥ 0.80 |


**For regression** — key metrics:


| Metric | What it means                                  |
| ------ | ---------------------------------------------- |
| MAE    | Average prediction error in outage ratio units |
| R²     | Variance explained (closer to 1.0 = better)    |
| RMSE   | Root mean squared error                        |


Also check:

- **Feature importance** — Wind speed and shear should rank highest
- **Confusion matrix** (classifier) — False negatives are more costly than false positives (missed outages vs unnecessary crew staging)

## Step 5: Deploy for Batch Prediction

For this use case, batch prediction is more appropriate than online endpoints (forecasts run daily, not per-request):

```bash
gcloud ai batch-predictions create \
  --display-name="outage-prediction-$(date +%Y%m%d)" \
  --model=$MODEL_ID \
  --input-format=bigquery \
  --input-path=bq://$GCP_PROJECT.$DATASET_NAME.bqml_training_data \
  --output-format=bigquery \
  --output-path=bq://$GCP_PROJECT.$DATASET_NAME.vertex_predictions \
  --project=$GCP_PROJECT \
  --region=us-central1
```

## Step 6: Join Predictions Back to Pipeline

**For classifier output:**

```sql
CREATE OR REPLACE VIEW `your-project.your_dataset.view_vertex_risk` AS
SELECT
  p.county_fips,
  p.valid_ts,
  p.predicted_outage_event.scores[OFFSET(1)] AS outage_probability,
  CASE
    WHEN p.predicted_outage_event.scores[OFFSET(1)] >= 0.7 THEN 'HIGH'
    WHEN p.predicted_outage_event.scores[OFFSET(1)] >= 0.3 THEN 'MEDIUM'
    ELSE 'LOW'
  END AS ml_risk_tier
FROM `your-project.your_dataset.vertex_predictions` p;
```

**For regressor output:**

```sql
CREATE OR REPLACE VIEW `your-project.your_dataset.view_vertex_risk` AS
SELECT
  p.county_fips,
  p.valid_ts,
  p.predicted_outage_ratio_6h_max AS predicted_ratio,
  CASE
    WHEN p.predicted_outage_ratio_6h_max >= 0.15 THEN 'SEVERE'
    WHEN p.predicted_outage_ratio_6h_max >= 0.05 THEN 'OUTAGE'
    ELSE 'NORMAL'
  END AS ml_risk_tier
FROM `your-project.your_dataset.vertex_predictions` p;
```

## Cost Estimates


| Component                            | Approximate Cost |
| ------------------------------------ | ---------------- |
| AutoML training (1 node-hour)        | $20              |
| Batch prediction (2-county, 10 days) | < $1             |
| Batch prediction (national, daily)   | $5–15/run        |
| Model storage (per month)            | < $1             |


## Comparison: BQML vs Vertex AI AutoML


| Aspect           | BQML Boosted Tree                  | Vertex AI AutoML                       |
| ---------------- | ---------------------------------- | -------------------------------------- |
| Setup complexity | Low (SQL only)                     | Medium (API/Console)                   |
| Training cost    | Free tier available                | ~$20/training run                      |
| Performance      | Good                               | Best (tries hundreds of architectures) |
| Explainability   | GLOBAL_EXPLAIN, feature importance | Feature importance, partial dependence |
| Inference        | ML.PREDICT in SQL                  | Batch prediction or endpoint           |
| Retraining       | Re-run SQL                         | Re-run training job                    |
| Best for         | Prototyping, SQL-first teams       | Production, maximum accuracy           |


