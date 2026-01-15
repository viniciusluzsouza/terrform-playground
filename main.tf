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

module "file_processor" {
  source = "./file-processor"

  # Input Variables
  bucket_name    = "s3-sns-sqs-vini-bucket"
  topic_name     = "sns-sqs-vini-topic"
  lambda_dir     = "${path.module}/lambda"
  lambda_handler = "lambda.lambda_handler"
  lambda_name    = "sns-sqs-lambda-function"
}
