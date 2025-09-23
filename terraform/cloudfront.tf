# --- CloudFront Origin Access Identity for S3 ---
resource "aws_cloudfront_origin_access_identity" "frontend_identity" {
  comment = "OAI for frontend S3 bucket"
}

# --- CloudFront Distribution for Frontend ---
resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true
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

