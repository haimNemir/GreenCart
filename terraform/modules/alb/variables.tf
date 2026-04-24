variable "name" {
  type        = string
  description = "Prefix/name for ALB resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID in which to create the ALB target group"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs for the ALB (must span at least 2 AZs)"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID to attach to the ALB"
}

variable "instance_ids" {
  type        = list(string)
  description = "List of application EC2 instance IDs to register as ALB targets"
}

variable "instance_count" {
  type        = number
  description = "Number of instances to attach to the target group (must match length of instance_ids)"
  default     = 2
}
