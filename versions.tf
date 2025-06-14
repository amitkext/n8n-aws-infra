terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "your-n8n-terraform-state" # Replace with your S3 bucket name
    key            = "n8n/terraform.tfstate"
    region         = "us-east-1" # Or your desired region
    dynamodb_table = "your-n8n-terraform-state" # Replace with your DynamoDB table name
    encrypt        = true
  }
}