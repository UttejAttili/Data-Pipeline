variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-2"
}

variable "project_name" {
  description = "Prefix used for naming resources"
  type        = string
  default     = "orders-data-pipeline"
}