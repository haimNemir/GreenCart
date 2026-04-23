variable "name" {
  type        = string
  description = "Prefix/name for EC2 and related resources"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for the MongoDB EC2 instance (RHEL 9.3)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "subnet_id" {
  type        = string
  description = "Private subnet ID in which to launch the MongoDB EC2 instance"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID to attach to the MongoDB EC2 instance"
}

variable "key_pair_name" {
  type        = string
  description = "EC2 key pair name — the same key pair used for the application instances, enabling jump-host SSH access"
}
