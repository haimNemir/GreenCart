resource "aws_key_pair" "this" {
  key_name   = "${var.name}-key"
  public_key = var.public_key # The public key is passed in from the build-infra.sh script, which reads it from ~/.ssh/greencart-key.pub on the admin machine. The private key never enters Terraform state.
}

resource "aws_instance" "app" {
  count                  = length(var.subnet_ids) # Create one instance per public subnet, placing each in a different Availability Zone.
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index]
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = var.instance_profile_name

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Docker CE on RHEL 9
    curl -fsSL https://download.docker.com/linux/rhel/docker-ce.repo \
      -o /etc/yum.repos.d/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Start Docker and enable it to run on every boot
    systemctl enable --now docker

    # Add ec2-user to the docker group so the CI/CD pipeline can run docker commands without sudo
    usermod -aG docker ec2-user

    # Download the application Docker Compose file so it is ready for the first CI/CD deployment
    curl -fsSL https://raw.githubusercontent.com/haimNemir/GreenCart/main/docker-compose.app.yml \
      -o /home/ec2-user/docker-compose.app.yml
    chown ec2-user:ec2-user /home/ec2-user/docker-compose.app.yml
  EOF

  tags = {
    Name    = "${var.name}-app-${count.index + 1}"
    Project = var.name
  }
}

resource "aws_eip" "app" {
  count  = length(aws_instance.app)
  domain = "vpc"

  tags = {
    Name    = "${var.name}-app-eip-${count.index + 1}"
    Project = var.name
  }
}

resource "aws_eip_association" "app" {
  count         = length(aws_instance.app)
  instance_id   = aws_instance.app[count.index].id
  allocation_id = aws_eip.app[count.index].id
}
