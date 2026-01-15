variable "bucket_name" {
    description = "S3 bucket name"
    type = string
}

variable "topic_name" {
    description = "SNS topic name. Also used for SQS name, which will be <topic_name>-queue"
    type = string
}

variable "lambda_dir" {
    description = "Lambda's code directory"
    type = string
}

variable "lambda_handler" {
    description = "Lambda's code handler"
    type = string
}

variable "lambda_name" {
    description = "Lambda resource name"
    type = string
}