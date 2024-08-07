terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.61.0"
    }
  }

  required_version = ">= 1.7.5"
}

provider "aws" {
  region = "ap-south-1"
}

# Create DynamoDB table
resource "aws_dynamodb_table" "dynamodb_object" {
  name         = "project_student_table"
  hash_key     = "id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "id"
    type = "S"
  }
}

# Read data.json content and create DynamoDB item content
#locals {
#  data_content = file("source.json")
#}

# Add item/content to the DynamoDB table using item id from local block
#resource "aws_dynamodb_table_item" "resume_json" {
#  table_name = aws_dynamodb_table.dynamodb_object.name
# hash_key   = "id"

#item = local.data_content

#depends_on = [aws_dynamodb_table.dynamodb_object]
#}

# Create IAM role for Lambda
resource "aws_iam_role" "iam_for_both_lambda" {
  name = "iam_lambda_object_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach AWSLambdaBasicExecutionRole policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.iam_for_both_lambda.name
}

# Attach AmazonS3FullAccess policy to Lambda role
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.iam_for_both_lambda.name
}

# Create DynamoDB read and write policy and attach to Lambda role
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "dynamodb_policy"
  role = aws_iam_role.iam_for_both_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Scan",
      ]
      Resource = aws_dynamodb_table.dynamodb_object.arn
    }]
  })
}

# Create Lambda function to get student data from dynamodb table with Python runtime
resource "aws_lambda_function" "get_lambda_function_object" {
  filename         = "project-get-student-Lambda.zip"
  function_name    = "project-get-student-Lambda"
  role             = aws_iam_role.iam_for_both_lambda.arn
  handler          = "lambda_get_function.lambda_handler"
  source_code_hash = filebase64sha256("project-get-student-Lambda.zip")
  runtime          = "python3.12"
  timeout          = "60"
}

# Create Lambda function to insert student data into dynamodb table with Python runtime
resource "aws_lambda_function" "insert_lambda_function_object" {
  filename         = "project-insert-student-Lambda.zip"
  function_name    = "project-insert-student-Lambda"
  role             = aws_iam_role.iam_for_both_lambda.arn
  handler          = "lambda_insert_function.lambda_handler"
  source_code_hash = filebase64sha256("project-insert-student-Lambda.zip")
  runtime          = "python3.12"
  timeout          = "60"
}


# Create S3 bucket
resource "aws_s3_bucket" "project_bucket_object" {
  bucket = "r2r-prj-std-bucket"
}

# Allow public access to the bucket
resource "aws_s3_bucket_public_access_block" "bucket_object_public_access" {
  bucket = aws_s3_bucket.project_bucket_object.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "website_object" {
  bucket = aws_s3_bucket.project_bucket_object.id

  index_document {
    suffix = "index.html"
  }
}

# Create Bucket policy to allow public access to index.html and restrict statefile access
resource "aws_s3_bucket_policy" "bucket_object_policy" {
  bucket = aws_s3_bucket.project_bucket_object.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "allow public access to the bucket objects",
        "Principal" : "*",
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : [
          "${aws_s3_bucket.project_bucket_object.arn}/*"
        ]
      },
      {
        "Sid" : "RestrictStateFileAccess",
        "Effect" : "Deny",
        "Principal" : "*",
        "Action" : "s3:*",
        "Resource" : "${aws_s3_bucket.project_bucket_object.arn}/terraform.tfstate"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.bucket_object_public_access
  ]
}

# Upload index.html to S3
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.project_bucket_object.id
  key    = "index.html"
  source = "index.html"

  depends_on = [
    aws_s3_bucket.project_bucket_object,
    aws_s3_bucket_public_access_block.bucket_object_public_access,
    aws_s3_bucket_policy.bucket_object_policy
  ]
}
# Upload source.json to S3
resource "aws_s3_object" "scripts_js" {
  bucket = aws_s3_bucket.project_bucket_object.id
  key    = "scripts.js"
  source = "scripts.js"

  depends_on = [
    aws_s3_bucket.project_bucket_object,
    aws_s3_bucket_public_access_block.bucket_object_public_access,
    aws_s3_bucket_policy.bucket_object_policy
  ]
}

# Create rest API
resource "aws_api_gateway_rest_api" "project-api" {
  name = "project-rest-api"
  description  = "this is regional rest api"
  endpoint_configuration {
    types            = ["REGIONAL"]
  }
}




resource "aws_api_gateway_resource" "student_resource" {
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  parent_id   = aws_api_gateway_rest_api.project-api.root_resource_id
  path_part   = "student"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.project-api.id
  resource_id   = aws_api_gateway_resource.student_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.project-api.id
  resource_id             = aws_api_gateway_resource.student_resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.get_lambda_function_object.invoke_arn
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.project-api.id
  resource_id   = aws_api_gateway_resource.student_resource.id
  http_method   = "POST"
  authorization = "NONE"
}


resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.project-api.id
  resource_id             = aws_api_gateway_resource.student_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.insert_lambda_function_object.invoke_arn
}
