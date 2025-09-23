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

# --- API Gateway Deployment and Stage ---
resource "aws_api_gateway_deployment" "chatbot_deployment" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.upload_integration.id,
      aws_api_gateway_integration.chat_integration.id
    ]))
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

resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = "my-chatbot-frontend-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}
