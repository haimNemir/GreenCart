resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false # Internet-facing: the ALB is the public entry point for the application.
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids # The ALB must span at least 2 subnets in different Availability Zones.

  tags = {
    Name    = "${var.name}-alb"
    Project = var.name
  }
}

resource "aws_lb_target_group" "this" {
  name     = "${var.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health" # The ALB checks the /health endpoint — nginx proxies it to Express, which returns 200 OK. This confirms the full application stack is alive, not just nginx.
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
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
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_target_group_attachment" "app" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = var.instance_ids[count.index]
  port             = 80
}
