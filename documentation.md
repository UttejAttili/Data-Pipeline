
### Event-Orchestrated ETL Pipeline with AWS Glue, Step Functions, SNS/SQS, and Terraform

---

## 1. Overview

This project implements a batch ETL pipeline for synthetic e-commerce order data, fully defined as Infrastructure-as-Code with Terraform. Raw order data lands in S3, gets cataloged by an AWS Glue crawler, transformed by a PySpark Glue job, and the whole sequence is orchestrated by an AWS Step Functions state machine — which also publishes success/failure notifications via SNS, fanned out to an SQS queue.

**IaC tool:** Terraform (local state)
**Sample data:** 508 rows of synthetic e-commerce orders, generated with Python's Faker library, deliberately including ~3% missing emails, ~2% negative quantities, ~2% null amounts, and 8 exact duplicate rows — to give the ETL job real cleaning work to do.

---

## 2. Architecture

```
S3 raw bucket (orders/sample_orders.csv)
        │
        ▼
Step Functions state machine
        │
        ├─► Glue Crawler ─────► Glue Data Catalog (schema/table registration)
        │
        ├─► Glue ETL Job (PySpark) ─────► S3 curated bucket (cleaned Parquet output)
        │
        └─► SNS Topic (success/failure) ─────► SQS Queue (durable status log)
```

**Flow, in order:**
1. The raw CSV sits in the `orders/` prefix of the raw S3 bucket.
2. A Step Functions execution starts (currently: manually triggered; not yet wired to an automatic S3-event trigger).
3. **StartCrawler** — the state machine starts the Glue crawler, which scans the raw CSV and registers/updates a table (`orders`) in the Glue Data Catalog, inferring its schema.
4. **GetCrawlerStatus / IsCrawlerDone / WaitForCrawler** — a polling loop: the state machine repeatedly checks the crawler's status every 15 seconds until it reports `READY`, rather than guessing a fixed wait time.
5. **StartETLJob** — once cataloged, the state machine starts the Glue ETL job (`.sync` — Step Functions waits for it to actually finish). The PySpark script reads the `orders` table from the Data Catalog, cleans it (deduplicates, filters invalid quantities, recomputes null amounts, handles missing emails), and writes the result as Parquet to the curated S3 bucket.
6. **NotifySuccess / NotifyFailure** — depending on whether the ETL job succeeded or the state machine caught an error anywhere in the chain (`Catch: States.ALL`), a message is published to the SNS topic.
7. SNS fans that message out to a subscribed SQS queue, where it durably waits for any downstream consumer.

---

## 3. AWS Resources Used


| Service | Resource(s) | Purpose |
|---|---|---|
| **S3** | `raw` bucket, `curated` bucket | Landing zone for raw data; destination for cleaned output |
| **IAM** | Glue service role, Step Functions service role, two custom policies | Least-privilege permissions for Glue and Step Functions to act on your behalf |
| **Glue** | Catalog database, crawler, ETL job | Schema discovery/registration; Spark-based transformation |
| **Step Functions** | One state machine | Orchestrates the crawler → job → notification sequence, with polling and error handling |
| **SNS** | One topic | Publishes pipeline status (success/failure) |
| **SQS** | One queue + queue policy | Durable subscriber to the SNS topic, for downstream consumption |

---

## 4. Step-by-Step Implementation Process

1. **AWS account and local environment setup** — AWS account created (after resolving an MFA lockout on a prior account and a PAN identity-verification snag on signup), MFA enabled, `terraform-admin` IAM user created with CLI access keys, AWS CLI configured, Git/GitHub repo set up, VS Code with Terraform/Python/AWS Toolkit extensions, Terraform installed via `winget`.
2. **S3 buckets** (`s3.tf`) — raw and curated buckets created first, since every other resource depends on them existing.
3. **Glue IAM role** (`glue_iam.tf`) — trust policy allowing `glue.amazonaws.com` to assume a role, plus a least-privilege custom policy scoped to exactly the two buckets (`ListBucket` at bucket level, `GetObject`/`PutObject` at object level).
4. **SNS + SQS** (`sns_sqs.tf`) — topic, queue, a queue policy scoped by `SourceArn` condition to only accept messages from this specific topic, and the subscription linking them.
5. **Glue database, crawler, ETL job, and script upload** (`glue.tf`, `glue_job.tf`) — the Data Catalog database, the sample CSV and PySpark script uploaded to S3 via `aws_s3_object`, the crawler pointed at the raw bucket's `orders/` prefix, and the Glue job configured to run the script with the database name and curated S3 path passed in as job parameters (not hardcoded).
6. **PySpark ETL script** (`transform_orders.py`) — reads the `orders` table from the Data Catalog, deduplicates, filters out invalid (non-positive) quantities, recomputes null `amount` values as `quantity * unit_price`, handles missing emails, and writes the result as Parquet to the curated bucket.
7. **Step Functions IAM role** (`sfn_iam.tf`) — trust policy for `states.amazonaws.com`, permissions for `glue:StartCrawler`/`GetCrawler`/`StartJobRun`/`GetJobRun` and `sns:Publish`.
8. **Step Functions state machine** (`step_functions.tf`) — the ASL (Amazon States Language) definition tying together the crawler, the job, and both notification branches, with a genuine polling loop for crawler completion rather than a fixed wait.
9. **Outputs** (`outputs.tf`) — surfaces the state machine ARN, both bucket names, the Glue database/crawler/job names, and the SNS topic ARN after `apply`.
10. **(Blocked)** `terraform apply` for the Glue and Step Functions resources — the AWS account currently returns `AccessDeniedException: Account is denied access` on any Glue resource creation, confirmed account-wide (tested identically in `ap-south-2` and `us-east-1`), with an AWS Support ticket filed to resolve it.
11. **(Pending)** end-to-end test run once unblocked, and eventually an automated S3-event trigger to replace manual execution starts.

---

## 5. File-by-File Reference

### Repository root
| File | Contents |
|---|---|
| `transform_orders.py` | The PySpark ETL script — reads the raw `orders` table from the Glue Data Catalog, cleans it, writes cleaned Parquet to the curated bucket |
| `data/sample_orders.csv` | 508 rows of synthetic order data (Faker-generated), including intentional messiness for the ETL job to clean |
| `.gitignore` | Excludes `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `.terraform.lock.hcl`, `*.tfvars` from version control |

### `terraform/`
| File | Contents |
|---|---|
| `provider.tf` | Declares the required AWS provider version and configures the region (via `var.aws_region`) |
| `variables.tf` | Input variables: `aws_region` (default `ap-south-2`) and `project_name` (default `orders-data-pipeline`) |
| `s3.tf` | `data.aws_caller_identity` (for unique bucket naming), `locals` for computed bucket names, the raw and curated `aws_s3_bucket` resources, versioning, and public-access-block configuration for both |
| `glue_iam.tf` | Glue service role: trust policy, AWS-managed `AWSGlueServiceRole` attachment, and a custom least-privilege S3 access policy scoped to the raw/curated buckets |
| `sns_sqs.tf` | SNS topic, SQS queue, the queue policy (scoped via `SourceArn` condition), and the SNS→SQS subscription |
| `glue.tf` | Glue Catalog database, the `aws_s3_object` upload of the sample CSV, the `aws_s3_object` upload of the transform script, and the Glue crawler resource |
| `glue_job.tf` | The `aws_glue_job` resource — references the uploaded script's S3 location, passes the Glue database name and curated S3 path as job parameters |
| `sfn_iam.tf` | Step Functions service role: trust policy for `states.amazonaws.com`, and permissions for the specific Glue and SNS actions the state machine needs |
| `step_functions.tf` | The `aws_sfn_state_machine` resource — the full ASL definition (crawler start → poll loop → ETL job → success/failure notification) |
| `outputs.tf` | Prints the state machine ARN, raw/curated bucket names, Glue database/crawler/job names, and SNS topic ARN after `apply` |

---

## 6. Next Steps

1. AWS Support resolves the account-level Glue restriction.
2. `terraform apply` the remaining resources (Glue database/crawler/job, Step Functions state machine).
3. Manually start a Step Functions execution via the console; verify the visual execution graph moves cleanly through each state.
4. Confirm the crawler registers the `orders` table correctly, and the ETL job writes clean Parquet output to the curated bucket.
5. Inspect the curated output (via Athena or direct S3/Parquet inspection) to confirm the cleaning logic worked as intended.
6. Design and implement an automated trigger so new files landing in the raw bucket kick off the pipeline without manual intervention.