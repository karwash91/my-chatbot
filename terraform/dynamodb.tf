resource "aws_dynamodb_table" "docs_table" {
  name         = "my-chatbot-docs"
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

  attribute {
    name = "filename"
    type = "S"
  }

  global_secondary_index {
    name            = "filename-index"
    hash_key        = "filename"
    projection_type = "ALL"
  }
}
