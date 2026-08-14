resource "aws_glue_job" "orders_transform" {
  name     = "${var.project_name}-orders-transform-job"
  role_arn = aws_iam_role.glue_service_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.raw.id}/${aws_s3_object.transform_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--GLUE_DATABASE"   = aws_glue_catalog_database.orders_db.name
    "--CURATED_S3_PATH" = "s3://${aws_s3_bucket.curated.id}/orders/"
    "--job-language"    = "python"
  }

  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"
}