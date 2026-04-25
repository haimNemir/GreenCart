variable "name" {
  type        = string
  description = "Prefix/name for EC2 and related resources"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for the application EC2 instances (Amazon Linux 2023)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs — one instance will be launched per subnet"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID to attach to the application EC2 instances"
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name for ECR pull access"
}

variable "public_key" {
  type        = string
  description = "SSH public key content for the EC2 key pair"
}

variable "instance_count" {
  type        = number
  description = "Number of application EC2 instances to create (must match length of subnet_ids)"
  default     = 2
}
