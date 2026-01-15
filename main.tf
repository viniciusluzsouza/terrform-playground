terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "terraform"
}

data "aws_iam_policy_document" "topic" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:${var.sns_topic}"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.bucket.arn]
    }
  }
}

### Bucket
resource "aws_s3_bucket" "bucket" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  topic {
    topic_arn     = aws_sns_topic.topic.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}

### SNS topic
resource "aws_sns_topic" "topic" {
  name   = var.sns_topic
  policy = data.aws_iam_policy_document.topic.json
}

### SQS queue
resource "aws_sqs_queue" "terraform_queue" {
  name                       = var.queue_name
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  delay_seconds              = 30
  receive_wait_time_seconds  = 0
  sqs_managed_sse_enabled    = true

  tags = {
    Environment = "production"
  }
}

resource "aws_sqs_queue_policy" "example_queue_policy" {
  queue_url = aws_sqs_queue.terraform_queue.id

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Id" : "sqspolicy",
      "Statement" : [
        {
          "Sid" : "001",
          "Effect" : "Allow",
          "Principal" : "*",
          "Action" : "sqs:SendMessage",
          "Resource" : aws_sqs_queue.terraform_queue.arn,
          "Condition" : {
            "ArnEquals" : {
              "aws:SourceArn" : aws_sns_topic.topic.arn
            }
          }
        }
      ]
  })
}

### SNS subscription
resource "aws_sns_topic_subscription" "example_topic_subscription" {
  topic_arn = aws_sns_topic.topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.terraform_queue.arn
}


####

# IAM role for Lambda execution
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }

}

resource "aws_iam_role_policy" "receive_sqs_message" {
  name = "receive_sqs_message_policy"
  role = aws_iam_role.lambda_iam.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = "${aws_sqs_queue.terraform_queue.arn}"
      },
    ]
  })
}

resource "aws_iam_role_policy" "create_logs" {
  name = "create_logs_policy"
  role = aws_iam_role.lambda_iam.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "lambda_iam" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Package the Lambda function code
data "archive_file" "lambda_zip_file" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/package"
  output_path = "${path.module}/lambda/lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "lambda_function" {
  filename      = data.archive_file.lambda_zip_file.output_path
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_iam.arn
  handler       = "lambda.lambda_handler"
  code_sha256   = data.archive_file.lambda_zip_file.output_base64sha256

  runtime = "python3.12"

  environment {
    variables = {
      ENVIRONMENT = "production"
      LOG_LEVEL   = "info"
    }
  }

  tags = {
    Environment = "production"
    Application = var.lambda_name
  }
}

### SQS trigger lambda
resource "aws_lambda_event_source_mapping" "sqs_lambda_trigger" {
  event_source_arn = aws_sqs_queue.terraform_queue.arn
  function_name    = aws_lambda_function.lambda_function.arn
  batch_size       = 1

  scaling_config {
    maximum_concurrency = 2
  }
}