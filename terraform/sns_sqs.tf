resource "aws_sns_topic" "pipeline_notifications" {
  name = "${var.project_name}-pipeline-notifications"
}

resource "aws_sqs_queue" "pipeline_status_queue" {
  name = "${var.project_name}-pipeline-status-queue"
}

# Policy allowing the SNS topic to send messages into this SQS queue
data "aws_iam_policy_document" "sqs_from_sns" {
  statement {
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.pipeline_status_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.pipeline_notifications.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "pipeline_status_queue" {
  queue_url = aws_sqs_queue.pipeline_status_queue.id
  policy    = data.aws_iam_policy_document.sqs_from_sns.json
}

# The actual subscription: tells SNS "forward messages to this SQS queue"
resource "aws_sns_topic_subscription" "sqs_subscription" {
  topic_arn = aws_sns_topic.pipeline_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.pipeline_status_queue.arn
}