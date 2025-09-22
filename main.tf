terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3"
}

provider "aws" {
  region = "us-east-1"
}

# --- S3 Bucket ---
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "docs_bucket" {
  bucket = "my-chatbot-docs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "docs_versioning" {
  bucket = aws_s3_bucket.docs_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- DynamoDB Tables ---
resource "aws_dynamodb_table" "docs_table" {
  name         = "my-chatbot-docs-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "doc_id"
  range_key    = "chunk_id"

  attribute {
    name = "doc_id"
    type = "S"
  }

  attribute {
    name = "chunk_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "answers_table" {
  name         = "my-chatbot-answers-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}

# --- SQS Queues ---
resource "aws_sqs_queue" "ingest_queue" {
  name = "my-chatbot-ingest-queue"

  tags = {
    Project = "my-chatbot"
  }
}

resource "aws_sqs_queue" "chat_queue" {
  name = "my-chatbot-chat-queue"

  tags = {
    Project = "my-chatbot"
  }
}

# --- Cognito User Pool ---
resource "aws_cognito_user_pool" "chatbot_pool" {
  name = "my-chatbot-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

# --- Cognito App Client ---
resource "aws_cognito_user_pool_client" "chatbot_client" {
  name            = "my-chatbot-client"
  user_pool_id    = aws_cognito_user_pool.chatbot_pool.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = [
    "openid",
    "email",
    "profile",
    "aws.cognito.signin.user.admin",
    "phone" # optional if you need phone claims
  ]
  allowed_oauth_flows_user_pool_client = true

  callback_urls = [
    "http://localhost:5173",
    "http://localhost:5173/",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/"
  ]

  logout_urls = [
    "http://localhost:5173",
    "http://localhost:5173/",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/"
  ]

  supported_identity_providers = ["COGNITO"]
}

# --- Cognito Domain ---
resource "aws_cognito_user_pool_domain" "chatbot_domain" {
  domain       = "my-chatbot-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.chatbot_pool.id
}

# --- IAM Role and Policies ---
resource "aws_iam_role" "lambda_role" {
  name = "my-chatbot-lambda-role-${random_id.suffix.hex}"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_extra" {
  name = "my-chatbot-lambda-extra"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:GetObject"],
        Resource = "${aws_s3_bucket.docs_bucket.arn}/*"
      },
      {
        Effect   = "Allow",
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
        Resource = aws_sqs_queue.ingest_queue.arn
      },
      {
        Effect   = "Allow",
        Action   = ["dynamodb:PutItem"],
        Resource = aws_dynamodb_table.docs_table.arn
      },
      {
        Effect   = "Allow",
        Action   = ["dynamodb:Scan"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
        Resource = [
          "*",
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["bedrock:ApplyGuardrail"],
        Resource = "arn:aws:bedrock:us-east-1:588738567290:guardrail/rqkveuut7fzm"
      }
    ]
  })
}

# --- Lambda Functions ---
resource "aws_lambda_function" "upload_lambda" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy.lambda_extra,
    aws_iam_role_policy_attachment.lambda_basic
  ]
  function_name = "my-chatbot-upload"
  role          = aws_iam_role.lambda_role.arn
  handler       = "upload.handler"
  runtime       = "python3.11"

  s3_bucket = aws_s3_bucket.docs_bucket.bucket
  s3_key    = "lambdas/upload.zip"

  environment {
    variables = {
      DOCS_BUCKET      = aws_s3_bucket.docs_bucket.bucket
      INGEST_QUEUE_URL = aws_sqs_queue.ingest_queue.id
    }
  }
}

resource "aws_lambda_function" "ingest_worker" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy.lambda_extra,
    aws_iam_role_policy_attachment.lambda_basic
  ]
  function_name = "my-chatbot-ingest-worker"
  role          = aws_iam_role.lambda_role.arn
  handler       = "ingest.handler"
  runtime       = "python3.11"

  s3_bucket = aws_s3_bucket.docs_bucket.bucket
  s3_key    = "lambdas/ingest.zip"

  environment {
    variables = {
      DOCS_BUCKET = aws_s3_bucket.docs_bucket.bucket
      DOCS_TABLE  = aws_dynamodb_table.docs_table.name
    }
  }
}

resource "aws_lambda_function" "chat_lambda" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy.lambda_extra,
    aws_iam_role_policy_attachment.lambda_basic
  ]
  function_name = "my-chatbot-chat"

  role    = aws_iam_role.lambda_role.arn
  handler = "chat.handler"
  runtime = "python3.11"
  timeout = 30

  s3_bucket = aws_s3_bucket.docs_bucket.bucket
  s3_key    = "lambdas/chat.zip"

  environment {
    variables = {
      DOC_TABLE = aws_dynamodb_table.docs_table.name
    }
  }
}

resource "aws_lambda_function" "fetch_lambda" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy.lambda_extra,
    aws_iam_role_policy_attachment.lambda_basic
  ]
  function_name = "my-chatbot-fetch"
  role          = aws_iam_role.lambda_role.arn
  handler       = "fetch.handler"
  runtime       = "python3.11"

  s3_bucket = aws_s3_bucket.docs_bucket.bucket
  s3_key    = "lambdas/fetch.zip"
}

# --- Lambda Event Source Mapping ---
resource "aws_lambda_event_source_mapping" "ingest_sqs_trigger" {
  event_source_arn = aws_sqs_queue.ingest_queue.arn
  function_name    = aws_lambda_function.ingest_worker.arn
  batch_size       = 1
}

# --- API Gateway ---
resource "aws_api_gateway_rest_api" "chatbot_api" {
  name        = "my-chatbot-api"
  description = "API for my-chatbot"
}

# /upload resource
resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  parent_id   = aws_api_gateway_rest_api.chatbot_api.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chatbot_api.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_lambda.invoke_arn
}

# --- CORS for POST /upload ---
resource "aws_api_gateway_method_response" "upload_post_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "upload_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
  depends_on = [
    aws_api_gateway_integration.upload_integration,
    aws_api_gateway_method_response.upload_post_response
  ]
}

resource "aws_api_gateway_method" "upload_options" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "upload_options_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "upload_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
  depends_on = [
    aws_api_gateway_integration.upload_options_integration,
    aws_api_gateway_method_response.upload_options_response
  ]
}

# /chat resource
resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  parent_id   = aws_api_gateway_rest_api.chatbot_api.root_resource_id
  path_part   = "chat"
}

resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "chat_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chatbot_api.id
  resource_id             = aws_api_gateway_resource.chat.id
  http_method             = aws_api_gateway_method.chat_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_lambda.invoke_arn
}

# --- CORS for POST /chat ---
resource "aws_api_gateway_method_response" "chat_post_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "chat_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
  depends_on = [
    aws_api_gateway_integration.chat_integration,
    aws_api_gateway_method_response.chat_post_response
  ]
}

resource "aws_api_gateway_method" "chat_options" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "chat_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "chat_options_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "chat_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
  depends_on = [
    aws_api_gateway_integration.chat_options_integration,
    aws_api_gateway_method_response.chat_options_response
  ]
}

# /fetch/{session_id} resource
resource "aws_api_gateway_resource" "fetch" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  parent_id   = aws_api_gateway_rest_api.chatbot_api.root_resource_id
  path_part   = "fetch"
}

resource "aws_api_gateway_resource" "fetch_id" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  parent_id   = aws_api_gateway_resource.fetch.id
  path_part   = "{session_id}"
}

resource "aws_api_gateway_method" "fetch_get" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.fetch_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "fetch_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chatbot_api.id
  resource_id             = aws_api_gateway_resource.fetch_id.id
  http_method             = aws_api_gateway_method.fetch_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.fetch_lambda.invoke_arn
}

# --- CORS for GET /fetch/{session_id} ---
resource "aws_api_gateway_method_response" "fetch_get_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.fetch_id.id
  http_method = aws_api_gateway_method.fetch_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "fetch_get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.fetch_id.id
  http_method = aws_api_gateway_method.fetch_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
  depends_on = [
    aws_api_gateway_integration.fetch_integration,
    aws_api_gateway_method_response.fetch_get_response
  ]
}

resource "aws_api_gateway_method" "fetch_options" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.fetch_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "fetch_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.fetch_id.id
  http_method = aws_api_gateway_method.fetch_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "fetch_options_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.fetch_id.id
  http_method = aws_api_gateway_method.fetch_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "fetch_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.fetch_id.id
  http_method = aws_api_gateway_method.fetch_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
  depends_on = [
    aws_api_gateway_integration.fetch_options_integration,
    aws_api_gateway_method_response.fetch_options_response
  ]
}

# --- API Gateway Deployment and Stage ---
resource "aws_api_gateway_deployment" "chatbot_deployment" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.upload_integration.id,
      aws_api_gateway_integration.chat_integration.id,
      aws_api_gateway_integration.fetch_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_api_gateway_stage" "chatbot_stage" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  deployment_id = aws_api_gateway_deployment.chatbot_deployment.id
  stage_name    = "dev"
}

# --- Lambda Permissions for API Gateway ---
resource "aws_lambda_permission" "apigw_upload" {
  statement_id  = "AllowAPIGatewayInvokeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.chatbot_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_chat" {
  statement_id  = "AllowAPIGatewayInvokeChat"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.chatbot_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_fetch" {
  statement_id  = "AllowAPIGatewayInvokeFetch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fetch_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.chatbot_api.execution_arn}/*/*"
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "my-chatbot-frontend-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_website_configuration" "frontend_bucket_website" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_bucket_block" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend_bucket.bucket
}

# --- CloudFront Origin Access Identity for S3 ---
resource "aws_cloudfront_origin_access_identity" "frontend_identity" {
  comment = "OAI for frontend S3 bucket"
}

# --- S3 Bucket Policy: Only allow CloudFront OAI ---
resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          "AWS" = aws_cloudfront_origin_access_identity.frontend_identity.iam_arn
        },
        Action   = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}

# --- ACM Certificate for CloudFront (must be in us-east-1) ---
resource "aws_acm_certificate" "frontend_cert" {
  domain_name       = "chatbot.yourdomain.com"
  validation_method = "DNS"
  # NOTE: DNS validation must be performed manually via your domain registrar.
}

# --- CloudFront Distribution for Frontend ---
resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for frontend static site"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "frontendS3Origin"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend_identity.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "frontendS3Origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "frontend_url" {
  value = aws_s3_bucket_website_configuration.frontend_bucket_website.website_endpoint
}

output "frontend_cdn_url" {
  value = aws_cloudfront_distribution.frontend_cdn.domain_name
}

output "frontend_cdn_id" {
  value = aws_cloudfront_distribution.frontend_cdn.id
}

output "docs_bucket_name" {
  value = aws_s3_bucket.docs_bucket.bucket
}

output "docs_table_name" {
  value = aws_dynamodb_table.docs_table.name
}

output "answers_table_name" {
  value = aws_dynamodb_table.answers_table.name
}

output "lambda_role_name" {
  value = aws_iam_role.lambda_role.name
}

