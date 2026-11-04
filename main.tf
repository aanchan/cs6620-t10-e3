# Assignment 3 setup: Lambda service + SNS email topic.
# Run in AWS CloudShell (us-east-1), in a folder with lambda_function.py.
#
#   terraform init
#   terraform apply -var="nuid=<NUID>" -var="email=<EMAIL>"
#
# Clean up:  terraform destroy -var="nuid=<NUID>" -var="email=<EMAIL>"

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "nuid" {
  description = "Your NUID. Used in every resource name, and decides how your service breaks."
  type        = string
}

variable "email" {
  description = "Where alarm emails go."
  type        = string
}

data "aws_caller_identity" "me" {}

locals {
  name = "obs-lab-${var.nuid}"
  # Learner Lab can't create IAM roles, so we use the existing LabRole.
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/LabRole"
}

# --- The service ---

data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/fn.zip"
}

# Created up front so `terraform destroy` also removes the logs.
resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "fn" {
  function_name    = local.name
  role             = local.lab_role_arn
  runtime          = "python3.12"
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      SEED = var.nuid
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn]
}

# One test request, so Lambda's metrics show up in CloudWatch.
resource "aws_lambda_invocation" "smoke_test" {
  function_name = aws_lambda_function.fn.function_name
  input         = jsonencode({ route = "user", item_id = 1 })
}

# --- Email alerts ---

resource "aws_sns_topic" "alerts" {
  name = "obs-topic-${var.nuid}" # Standard topic. FIFO can't send email.
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email
}

# --- Outputs ---

output "function_name" {
  value = aws_lambda_function.fn.function_name
}

output "log_group" {
  value = aws_cloudwatch_log_group.fn.name
}

output "sns_topic" {
  value = aws_sns_topic.alerts.name
}

output "next_step" {
  value = "Check ${var.email} and click 'Confirm subscription'."
}
