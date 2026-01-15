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
  source_dir  = "${var.lambda_dir}/package"
  output_path = "${var.lambda_dir}/lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "lambda_function" {
  filename      = data.archive_file.lambda_zip_file.output_path
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_iam.arn
  handler       = var.lambda_handler
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