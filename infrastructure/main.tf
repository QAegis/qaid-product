provider "aws" {
  region = "us-east-1"
}

variable "backend_image" {
  type = string
}

variable "frontend_image" {
  type = string
}

# ECS Cluster
resource "aws_ecs_cluster" "qaid_cluster" {
  name = "qaid-product-cluster"
}

# Backend Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "qaid-product-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.backend_image
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "DATABASE_URL", value = aws_rds_cluster.database.endpoint }
      ]
      secrets = [
        { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
}

# Frontend S3 Bucket
resource "aws_s3_bucket" "frontend" {
  bucket = "qaid-product-frontend"
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend.id
  
  index_document {
    suffix = "index.html"
  }
  
  error_document {
    key = "index.html"
  }
}

# CloudFront Distribution for Frontend
resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend_website.website_endpoint
    origin_id   = "S3-Website"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Website"
    
    forwarded_values {
      query_string = false
      
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Database
resource "aws_rds_cluster" "database" {
  cluster_identifier      = "qaid-product-db"
  engine                  = "aurora-postgresql"
  engine_mode             = "serverless"
  database_name           = "qaid_production"
  master_username         = "admin"
  master_password         = aws_secretsmanager_secret_version.db_password.secret_string
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = true
  
  scaling_configuration {
    auto_pause               = true
    min_capacity             = 2
    max_capacity             = 8
    seconds_until_auto_pause = 300
  }
}

# Secrets
resource "aws_secretsmanager_secret" "db_password" {
  name = "qaid-product/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = "YourSecurePasswordHere123!"  # In production, use a secure method to handle this
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "qaid-product/jwt-secret"
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = "YourSecureJWTSecretHere"  # In production, use a secure method to handle this
}

# Output
output "api_endpoint" {
  value = aws_alb.api_alb.dns_name
}

output "frontend_url" {
  value = aws_cloudfront_distribution.frontend.domain_name
}