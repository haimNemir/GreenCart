variable "public_key" {
  type        = string
  description = "SSH public key content for the EC2 key pair — read from ~/.ssh/greencart-key.pub by build-infra.sh"
  default     = ""
}
