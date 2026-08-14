data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn_service_role" {
  name               = "${var.project_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

data "aws_iam_policy_document" "sfn_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "glue:StartCrawler",
      "glue:GetCrawler",
      "glue:StartJobRun",
      "glue:GetJobRun"
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.pipeline_notifications.arn]
  }
}

resource "aws_iam_policy" "sfn_permissions" {
  name   = "${var.project_name}-sfn-permissions"
  policy = data.aws_iam_policy_document.sfn_permissions.json
}

resource "aws_iam_role_policy_attachment" "sfn_permissions" {
  role       = aws_iam_role.sfn_service_role.name
  policy_arn = aws_iam_policy.sfn_permissions.arn
}


resource "aws_sfn_state_machine" "orders_pipeline" {
  name     = "${var.project_name}-orders-pipeline"
  role_arn = aws_iam_role.sfn_service_role.arn

  definition = <<EOF
{
  "Comment": "Orders ETL pipeline",
  "StartAt": "StartCrawler",
  "States": {
    "StartCrawler": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:glue:startCrawler",
      "Parameters": {
        "Name": "${aws_glue_crawler.orders_raw_crawler.name}"
      },
      "Next": "GetCrawlerStatus"
    },
    "GetCrawlerStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:glue:getCrawler",
      "Parameters": {
        "Name": "${aws_glue_crawler.orders_raw_crawler.name}"
      },
      "Next": "IsCrawlerDone"
    },
    "IsCrawlerDone": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.Crawler.State",
          "StringEquals": "READY",
          "Next": "StartETLJob"
        }
      ],
      "Default": "WaitForCrawler"
    },
    "WaitForCrawler": {
      "Type": "Wait",
      "Seconds": 15,
      "Next": "GetCrawlerStatus"
    },
    "StartETLJob": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${aws_glue_job.orders_transform.name}"
      },
      "Next": "NotifySuccess",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure"
        }
      ]
    },
    "NotifySuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.pipeline_notifications.arn}",
        "Message": "Orders pipeline completed successfully"
      },
      "End": true
    },
    "NotifyFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.pipeline_notifications.arn}",
        "Message": "Orders pipeline failed"
      },
      "End": true
    }
  }
}
EOF
}