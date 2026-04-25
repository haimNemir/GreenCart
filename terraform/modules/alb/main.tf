resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false # Prevent from the ALB from being created as an internal load balancer, instead of open to the internet. 
  load_balancer_type = "application" # NLB not needed because we don't need TCP/UDP support, and ALB is cheaper for HTTP traffic. and also we serving HTTP traffic, so ALB is a better fit.
  # This SG is open to all in both ways. Every each resources in AWS must have a SG there for 
  # we define it.
  security_groups    = [var.security_group_id] 
  subnets            = var.subnet_ids # The ALB must span at least 2 subnets in different Availability Zones.

  tags = {
    Name    = "${var.name}-alb"
    Project = var.name
  }
}

resource "aws_lb_target_group" "this" {
  name     = "${var.name}-tg"
  port     = 80 # The ALB will forward incoming HTTP traffic on port 80.
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health" # The ALB checks the /health endpoint — nginx proxies it to Express, which returns 200 OK. This confirms the full application stack is alive, not just nginx.
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    # The ALB considers a target healthy after 2 consecutive successful health checks, 
    # and unhealthy after 2 consecutive failures.
    healthy_threshold   = 2 
    unhealthy_threshold = 2
  }

  tags = {
    Name    = "${var.name}-tg"
    Project = var.name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80 # The ALB listens for incoming HTTP traffic on port 80.
  protocol          = "HTTP"

  default_action {
    type             = "forward" 
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_target_group_attachment" "app" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = var.instance_ids[count.index]
  port             = 80
}
