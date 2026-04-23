# ---- ALB Security Group ----

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Security group for the ALB — allows public HTTP traffic inbound"
  vpc_id      = var.vpc_id

  tags = {
    Name    = "${var.name}-alb-sg"
    Project = var.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Allow public HTTP traffic from the internet"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # Allow all outbound traffic from the ALB to reach the backend instances.
  description       = "Allow all outbound traffic"
}

# ---- Application Instances Security Group ----

resource "aws_security_group" "app" {
  name        = "${var.name}-app-sg"
  description = "Security group for application EC2 instances — nginx and Express containers"
  vpc_id      = var.vpc_id

  tags = {
    Name    = "${var.name}-app-sg"
    Project = var.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id # Accept traffic only from the ALB security group, not from the internet directly.
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "Allow HTTP traffic from the ALB"
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = var.admin_cidr # Restrict SSH to the administrator's current public IP only.
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Allow SSH access from the admin IP"
}

resource "aws_vpc_security_group_egress_rule" "app_all_outbound" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # Allow all outbound so the instances can reach ECR, Docker Hub, and the MongoDB EC2.
  description       = "Allow all outbound traffic"
}

# ---- DB Instance Security Group ----

resource "aws_security_group" "db" {
  name        = "${var.name}-db-sg"
  description = "Security group for the MongoDB EC2 instance — no direct internet access"
  vpc_id      = var.vpc_id

  tags = {
    Name    = "${var.name}-db-sg"
    Project = var.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_mongo_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id # Accept MongoDB connections only from the application instances, never from the internet.
  from_port                    = 27017
  to_port                      = 27017
  ip_protocol                  = "tcp"
  description                  = "Allow MongoDB access from application instances"
}

resource "aws_vpc_security_group_ingress_rule" "db_ssh_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id # SSH is allowed only through the application instance as a jump host, not from the internet.
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "Allow SSH jump-host access from application instances"
}

resource "aws_vpc_security_group_egress_rule" "db_all_outbound" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # Allow all outbound so the MongoDB instance can pull Docker images via the NAT Gateway.
  description       = "Allow all outbound traffic"
}
