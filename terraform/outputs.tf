output "state_machine_arn" {
  description = "ARN of the Step Functions state machine — needed to start an execution"
  value       = aws_sfn_state_machine.orders_pipeline.arn
}

output "raw_bucket_name" {
  description = "Name of the raw S3 bucket"
  value       = aws_s3_bucket.raw.id
}

output "curated_bucket_name" {
  description = "Name of the curated S3 bucket"
  value       = aws_s3_bucket.curated.id
}

output "glue_database_name" {
  description = "Glue Data Catalog database name"
  value       = aws_glue_catalog_database.orders_db.name
}

output "glue_crawler_name" {
  description = "Name of the Glue crawler"
  value       = aws_glue_crawler.orders_raw_crawler.name
}

output "glue_job_name" {
  description = "Name of the Glue ETL job"
  value       = aws_glue_job.orders_transform.name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for pipeline notifications"
  value       = aws_sns_topic.pipeline_notifications.arn
}