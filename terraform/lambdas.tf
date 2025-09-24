# --- Lambda Functions ---
resource "aws_lambda_function" "upload_lambda" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_extra
  ]
  function_name = "my-chatbot-upload"
  role          = aws_iam_role.lambda_role.arn
  handler       = "upload.handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../lambdas/upload.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambdas/upload.zip")

  environment {
    variables = {
      DOCS_BUCKET      = aws_s3_bucket.docs_bucket.bucket
      INGEST_QUEUE_URL = aws_sqs_queue.ingest_queue.id
    }
  }
}

resource "aws_lambda_function" "ingest_lambda" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_extra
  ]
  function_name = "my-chatbot-ingest"
  role          = aws_iam_role.lambda_role.arn
  handler       = "ingest.handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../lambdas/ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambdas/ingest.zip")

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
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_extra
  ]
  function_name = "my-chatbot-chat"

  memory_size = 1024

  role    = aws_iam_role.lambda_role.arn
  handler = "chat.handler"
  runtime = "python3.11"
  timeout = 30

  filename         = "${path.module}/../lambdas/chat.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambdas/chat.zip")

  environment {
    variables = {
      DOC_TABLE = aws_dynamodb_table.docs_table.name
    }
  }
}

# --- Lambda Event Source Mapping ---
resource "aws_lambda_event_source_mapping" "ingest_sqs_trigger" {
  event_source_arn = aws_sqs_queue.ingest_queue.arn
  function_name    = aws_lambda_function.ingest_lambda.arn
  batch_size       = 1

  depends_on = [
    aws_lambda_function.ingest_lambda,
    aws_sqs_queue.ingest_queue
  ]

  lifecycle {
    create_before_destroy = false
  }
}
