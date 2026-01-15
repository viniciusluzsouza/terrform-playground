data "aws_iam_policy_document" "topic" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:${var.topic_name}"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.bucket.arn]
    }
  }
}

### SNS topic
resource "aws_sns_topic" "topic" {
  name   = var.topic_name
  policy = data.aws_iam_policy_document.topic.json
}

### SQS queue
resource "aws_sqs_queue" "terraform_queue" {
  name                       = "${var.topic_name}-queue"
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

### Bucket notification
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  topic {
    topic_arn     = aws_sns_topic.topic.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}