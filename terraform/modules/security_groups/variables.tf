variable "name" {
  type        = string
  description = "Prefix/name for security group resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID in which to create the security groups"
}

variable "admin_cidr" {
  type        = string
  description = "CIDR block allowed SSH access to the application EC2 instances"
}
