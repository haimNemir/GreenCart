resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id # Private subnet — the MongoDB instance has no direct internet access.
  vpc_security_group_ids = [var.security_group_id] # This SG allows inbound traffic only from the application instances SG's ID for port 27017 (to connect to MongoDB) and port 22 (for SSH to the jump host).
  key_name               = var.key_pair_name # Same key pair as the application instances, enabling the two-hop jump-host SSH pattern.

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

    usermod -aG docker ec2-user

    # Create the directory for the MongoDB seed script
    mkdir -p /home/ec2-user/mongo

    # Download the Compose file and the seed script from the public GitHub repository.
    # Outbound internet access is provided by the NAT Gateway — no authentication required
    # And because the repository is public you can use curl without any authentication tokens.
    curl -fsSL https://raw.githubusercontent.com/haimNemir/GreenCart/main/docker-compose.db.yml \
      -o /home/ec2-user/docker-compose.db.yml
    curl -fsSL https://raw.githubusercontent.com/haimNemir/GreenCart/main/mongo/init.js \
      -o /home/ec2-user/mongo/init.js

    chown -R ec2-user:ec2-user /home/ec2-user

    # Start MongoDB. On first boot, the official MongoDB image will automatically
    # execute the init script mounted into /docker-entrypoint-initdb.d, seeding the database.
    cd /home/ec2-user
    docker compose -f docker-compose.db.yml up -d
  EOF

  lifecycle {
    # This prevents Terraform from trying to replace the EC2 instance just because AWS 
    # releases a new AMI version of Amazon Linux 2023, which would cause the instance to be
    # terminated and replaced.
    ignore_changes = [ami] 
  }

  tags = {
    Name    = "${var.name}-db"
    Project = var.name
  }
}
