resource "aws_key_pair" "this" {
  key_name   = "${var.name}-key"

    # The public key get's his value from the "build-infra.sh" script, which reads it from 
    # "~/.ssh/greencart-key.pub" in my local machine. The same one is passed to the "ec2_db", 
    # so SSH just works between the app and the db.  
  public_key = var.public_key # The public key is passed in from the build-infra.sh script, which reads it from ~/.ssh/greencart-key.pub on the admin machine. The private key never enters Terraform state.
}

resource "aws_instance" "app" {
  count                  = length(var.subnet_ids) # Create one instance per public subnet, placing each in a different Availability Zone.
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index]
    
  # This SG allows inbound traffic on port 80 from  the ALB SG, and SSH access on port 22 
  # to all IPs also. The reason we allow SSH from all IPs is to enable to the CI pipeline to connect 
  # with SSH to the app instances and run docker-compose commands, and we can't predict the dynamic 
  # IPs of the CI runners because they are allways changing
  vpc_security_group_ids = [var.security_group_id] 
  key_name               = aws_key_pair.this.key_name
    
  # iam_instance_profile - attaches an IAM Role to the EC2 instance, And its make AWS to 
  # injects temporary, auto-rotating credentials onto the instance. So he can pull the 
  # new app image from ECR.
  iam_instance_profile   = var.instance_profile_name

  # user_data - The script that runs on the EC2 instance at launch time. 
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Docker on Amazon Linux 2023
    dnf install -y docker
    systemctl enable --now docker

    # Install Docker Compose v2 plugin
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Add ec2-user to the docker group so the CI/CD pipeline can run docker commands without sudo
    usermod -aG docker ec2-user

    # Download the application Docker Compose file from GitHub so it is ready for the first CI/CD deployment
    curl -fsSL https://raw.githubusercontent.com/haimNemir/GreenCart/main/docker-compose.app.yml \
      -o /home/ec2-user/docker-compose.app.yml
    chown ec2-user:ec2-user /home/ec2-user/docker-compose.app.yml
  EOF

  lifecycle {
    # This prevents Terraform from trying to replace the EC2 instance just because AWS 
    # releases a new AMI version of Amazon Linux 2023, which would cause the instance to be
    # terminated and replaced.
    ignore_changes = [ami] 
  }

  tags = {
    Name    = "${var.name}-app-${count.index + 1}"
    Project = var.name
  }
}

resource "aws_eip" "app" {
  count  = var.instance_count
  domain = "vpc"

  tags = {
    Name    = "${var.name}-app-eip-${count.index + 1}"
    Project = var.name
  }
}

resource "aws_eip_association" "app" {
  count         = var.instance_count
  instance_id   = aws_instance.app[count.index].id
  allocation_id = aws_eip.app[count.index].id
}
