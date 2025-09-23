# --- Cognito User Pool ---
resource "aws_cognito_user_pool" "chatbot_pool" {
  name = "my-chatbot-user-pool"

  auto_verified_attributes = ["email"]

  schema {
    attribute_data_type      = "String"
    name                     = "email"
    required                 = true
    developer_only_attribute = false
    mutable                  = true
  }

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
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/callback"
  ]

  logout_urls = [
    "http://localhost:5173",
    "http://localhost:5173/",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/",
    "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/callback"
  ]

  supported_identity_providers  = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"
}


# --- Cognito Domain ---
resource "aws_cognito_user_pool_domain" "chatbot_domain" {
  domain       = "my-chatbot-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.chatbot_pool.id
}