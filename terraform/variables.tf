variable "admin_cidr" {
  type        = string
  description = "CIDR block of the administrator machine allowed SSH access to the application EC2 instances (e.g. 1.2.3.4/32)"
}

variable "public_key" {
  type        = string
  description = "SSH public key content for the EC2 key pair — read from ~/.ssh/greencart-key.pub by build-infra.sh"
}
