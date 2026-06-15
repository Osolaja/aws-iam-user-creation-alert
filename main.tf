terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }

  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_sns_topic" "iam_alerts" {
  name = "${var.project_name}-sns-topic"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.iam_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "${var.project_name}-cloudtrail-logs-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/*"

        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_cloudtrail" "iam_monitoring" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs_policy]
}

resource "aws_cloudwatch_event_rule" "iam_create_user_rule" {
  name        = "${var.project_name}-eventbridge-rule"
  description = "Detects IAM CreateUser events"

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["iam.amazonaws.com"]
      eventName   = ["CreateUser"]
    }
  })
}

resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.iam_create_user_rule.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.iam_alerts.arn

  input_transformer {

    input_paths = {
      username  = "$.detail.requestParameters.userName"
      eventtime = "$.detail.eventTime"
      region    = "$.region"
      creator   = "$.detail.userIdentity.type"
    }

    input_template = <<EOF
"IAM USER CREATED ALERT - User Created: <username> | Created By: <creator> | Region: <region> | Time: <eventtime> | Please verify this activity was authorized."
EOF
  }
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.iam_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "events.amazonaws.com"
        }

        Action   = "sns:Publish"
        Resource = aws_sns_topic.iam_alerts.arn
      }
    ]
  })
}