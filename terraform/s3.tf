resource "aws_s3_bucket" "docs_bucket" {
  bucket        = "my-chatbot-docs-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend_bucket_block" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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
