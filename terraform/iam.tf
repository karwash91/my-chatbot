resource "aws_iam_role" "lambda_role" {
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