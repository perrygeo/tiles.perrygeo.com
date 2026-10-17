# ── CloudFront cache + origin-request policies ───────────────────────────────
#
# Cache key and origin forwarding are split. Host stays in the cache key so each
# hostname is cached separately; X-Forwarded-For and cookies reach the origin
# without entering the cache key. TTLs are origin-driven: honor Cache-Control
# from nginx, cache nothing without it.

resource "aws_cloudfront_cache_policy" "tiles" {
  # Legacy policy name from the gateway this repo was extracted from. Keeping it
  # means the import is 1:1; rename in a later apply if desired.
  name        = "gateway-origin-driven"
  comment     = "Origin-driven TTLs; cache key = Host + query string (no cookies/X-Forwarded-For)"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Host"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

resource "aws_cloudfront_origin_request_policy" "tiles" {
  # Legacy policy name (see cache policy note above).
  name    = "gateway-forward-to-origin"
  comment = "Forward cookies, query string, and X-Forwarded-For to origin without caching on them"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["X-Forwarded-For"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# ── CloudFront distribution ──────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "tiles" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "tiles.perrygeo.com: nginx → martin"
  aliases         = [var.domain]

  origin {
    origin_id   = "tiles-ec2"
    domain_name = aws_eip.tiles.public_dns

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "tiles-ec2"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.tiles.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.tiles.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "tiles" }
}
