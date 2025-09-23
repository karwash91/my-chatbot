terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
  required_version = ">= 1.3"
  backend "s3" {
    bucket = "karwash91-tfstate"
    key    = "chatbot/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}


data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
