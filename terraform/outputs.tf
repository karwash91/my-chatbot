output "frontend_bucket" {
  value = aws_s3_bucket.frontend_bucket.bucket
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

output "lambda_role_name" {
  value = aws_iam_role.lambda_role.name
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.chatbot_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.chatbot_domain.domain
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.chatbot_pool.id
}

output "cognito_issuer_url" {
  value = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.chatbot_pool.id}"
}

output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.chatbot_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.chatbot_stage.stage_name}"
}

