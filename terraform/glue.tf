resource "aws_glue_catalog_database" "orders_db" {
  name = "${var.project_name}-orders-db-glue-catalog"
}

resource "aws_s3_object" "sample_orders" {
  bucket = aws_s3_bucket.raw.id
  key    = "orders/sample_orders.csv"
  source = "../data/sample_orders.csv" # path relative to your terraform/ folder — adjust if yours differs
  etag   = filemd5("../data/sample_orders.csv")
}


resource "aws_s3_object" "transform_script" {
  bucket = aws_s3_bucket.raw.id
  key    = "scripts/transform_orders.py"
  source = "../transform_orders.py"
  etag   = filemd5("../transform_orders.py")
}

resource "aws_glue_crawler" "orders_raw_crawler" {
  name          = "${var.project_name}-orders-raw-crawler"
  role          = aws_iam_role.glue_service_role.arn
  database_name = aws_glue_catalog_database.orders_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.raw.id}/orders/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}