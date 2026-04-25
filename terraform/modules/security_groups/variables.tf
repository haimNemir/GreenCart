variable "name" {
  type        = string
  description = "Prefix/name for security group resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID in which to create the security groups"
}
