variable "cluster_name" {
  type        = string
  default     = "dev-eks-cluster"
}

variable "cluster_version" {
  type        = string
  default     = "1.29"
}
# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1" # or your preferred region
}
