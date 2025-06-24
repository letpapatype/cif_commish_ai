terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "sports-handbook-qa"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# S3 Bucket for PDF storage
resource "aws_s3_bucket" "pdf_storage" {
  bucket = "${var.project_name}-pdfs-${var.environment}-${random_string.bucket_suffix.result}"
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_notification" "pdf_upload_notification" {
  bucket = aws_s3_bucket.pdf_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.pdf_ingestion.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".pdf"
  }
}

# OpenSearch Domain
resource "aws_opensearch_domain" "handbook_search" {
  domain_name    = "${var.project_name}-${var.environment}"
  engine_version = "OpenSearch_2.3"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 20
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "es:*"
        Effect = "Allow"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-${var.environment}/*"
        Principal = {
          AWS = [
            aws_iam_role.lambda_ingestion_role.arn,
            aws_iam_role.lambda_qa_role.arn
          ]
        }
      }
    ]
  })
}

# SNS Topic for Q&A responses
resource "aws_sns_topic" "qa_responses" {
  name = "${var.project_name}-responses-${var.environment}"
}

# IAM Role for PDF Ingestion Lambda
resource "aws_iam_role" "lambda_ingestion_role" {
  name = "${var.project_name}-ingestion-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_ingestion_policy" {
  name = "${var.project_name}-ingestion-policy-${var.environment}"
  role = aws_iam_role.lambda_ingestion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.pdf_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet"
        ]
        Resource = "${aws_opensearch_domain.handbook_search.arn}/*"
      }
    ]
  })
}

# IAM Role for Q&A Lambda
resource "aws_iam_role" "lambda_qa_role" {
  name = "${var.project_name}-qa-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_qa_policy" {
  name = "${var.project_name}-qa-policy-${var.environment}"
  role = aws_iam_role.lambda_qa_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpGet"
        ]
        Resource = "${aws_opensearch_domain.handbook_search.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.qa_responses.arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Python PDF Ingestion Lambda
resource "aws_lambda_function" "pdf_ingestion" {
  filename         = "pdf-ingestion-lambda.zip"
  function_name    = "${var.project_name}-pdf-ingestion-${var.environment}"
  role            = aws_iam_role.lambda_ingestion_role.arn
  handler         = "handler.lambda_handler"
  source_code_hash = data.archive_file.pdf_ingestion_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 1024

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.handbook_search.endpoint
      AWS_REGION         = var.aws_region
    }
  }
}

# .NET Q&A Lambda
resource "aws_lambda_function" "qa_lambda" {
  filename         = "qa-lambda.zip"
  function_name    = "${var.project_name}-qa-${var.environment}"
  role            = aws_iam_role.lambda_qa_role.arn
  handler         = "QALambda::QALambda.Function::FunctionHandler"
  source_code_hash = data.archive_file.qa_lambda_zip.output_base64sha256
  runtime         = "dotnet8"
  timeout         = 30
  memory_size     = 512

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.handbook_search.endpoint
      SNS_TOPIC_ARN      = aws_sns_topic.qa_responses.arn
      AWS_REGION         = var.aws_region
    }
  }
}

# API Gateway for Q&A
resource "aws_api_gateway_rest_api" "qa_api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "API for sports handbook Q&A"
}

resource "aws_api_gateway_resource" "qa_resource" {
  rest_api_id = aws_api_gateway_rest_api.qa_api.id
  parent_id   = aws_api_gateway_rest_api.qa_api.root_resource_id
  path_part   = "ask"
}

resource "aws_api_gateway_method" "qa_method" {
  rest_api_id   = aws_api_gateway_rest_api.qa_api.id
  resource_id   = aws_api_gateway_resource.qa_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "qa_integration" {
  rest_api_id = aws_api_gateway_rest_api.qa_api.id
  resource_id = aws_api_gateway_resource.qa_resource.id
  http_method = aws_api_gateway_method.qa_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.qa_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "qa_deployment" {
  depends_on = [aws_api_gateway_integration.qa_integration]

  rest_api_id = aws_api_gateway_rest_api.qa_api.id
  stage_name  = var.environment
}

# Lambda permissions
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pdf_ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.pdf_storage.arn
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.qa_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.qa_api.execution_arn}/*/*"
}

# Data sources for packaging
data "archive_file" "pdf_ingestion_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-ingestion/src"
  output_path = "pdf-ingestion-lambda.zip"
}

data "archive_file" "qa_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-qa-dotnet/src/bin/Release/net8.0/publish"
  output_path = "qa-lambda.zip"
}

data "aws_caller_identity" "current" {}

# Outputs
output "s3_bucket_name" {
  value = aws_s3_bucket.pdf_storage.bucket
}

output "opensearch_endpoint" {
  value = aws_opensearch_domain.handbook_search.endpoint
}

output "api_gateway_url" {
  value = "${aws_api_gateway_deployment.qa_deployment.invoke_url}/ask"
}

output "sns_topic_arn" {
  value = aws_sns_topic.qa_responses.arn
}