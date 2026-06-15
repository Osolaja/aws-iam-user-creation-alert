variable "aws_region" {
  description = "AWS region for the project"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address to receive alerts"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "iam-user-creation-alert"
}