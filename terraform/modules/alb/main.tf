
module "http_sg" {
  source        = "../security_group"
  name          = "http-sg"
  vpc_id        = var.vpc_id
  port          = 80
  cidr_blocks   = ["0.0.0.0/0"]
}

module "https_sg" {
  source        = "../security_group"
  name          = "https-sg"
  vpc_id        = var.vpc_id
  port          = 443
  cidr_blocks   = ["0.0.0.0/0"]
}

resource "aws_lb" "main" {
  name = var.name
  load_balancer_type = "application"
  internal = false
  idle_timeout = 60
  # enable_deletion_protection = true
  enable_deletion_protection = false

  subnets = var.subnet_ids

#   access_logs {
#     bucket  = aws_s3_bucket.alb_log.id
#     enabled = true
#   }

  security_groups = [
    module.http_sg.security_group_id,
    module.https_sg.security_group_id,
  ]
}

# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type    = "fixed-response"
#     fixed_response {
#       content_type = "text/plain"
#       message_body = "http alb listener fixed response"
#       status_code  = "200"
#     }
#   }
# }

data "aws_route53_zone" "main" {
  name = "${var.root_domain_name}"
}

resource "aws_route53_record" "web_backend" {
  zone_id   = data.aws_route53_zone.main.zone_id
  name      = "${var.subdomain_name}.${data.aws_route53_zone.main.name}"
  type      = "A"

  alias {
    name                    = aws_lb.main.dns_name
    zone_id                 = aws_lb.main.zone_id
    evaluate_target_health  = true
  }
}

resource "aws_lb_target_group" "backend_lb_tgt_grp" {
  name                  = "backend-lb-tgt-grp"
  target_type           = "ip"
  vpc_id                = var.vpc_id
  port                  = 80
  protocol              = "HTTP"
  deregistration_delay  = 300

  health_check {
    path                = "/"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = 200
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  depends_on = [
    aws_lb.main
  ]
}

# resource "aws_lb_listener_rule" "http" {
#   listener_arn = aws_lb_listener.http.arn
#   priority = 100

#   action {
#     type = "forward"
#     target_group_arn = backend_lb_tgt_grp.web_lb_tgt_grp.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/*"]
#     }
#   }
# }

## HTTPS 

resource "aws_acm_certificate" "web_https" {
  domain_name = aws_route53_record.web_backend.name
  subject_alternative_names = []
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.web_https.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.web_https.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port = "443"
  protocol = "HTTPS"
  certificate_arn = aws_acm_certificate.web_https.arn
  ssl_policy = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "https fixed response"
      status_code = "200"
    }
  }

  depends_on = [
    aws_acm_certificate_validation.cert
  ]
}

resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.main.arn
  port = "80"
  protocol = "HTTP"
  
  default_action {
    type = "redirect"

    redirect {
      port = "443"
      protocol = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener_rule" "https" {
  listener_arn = aws_lb_listener.https.arn
  priority = 100

  action {
    type = "forward"
    target_group_arn = backend_lb_tgt_grp.web_lb_tgt_grp.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

######

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "domain_name" {
  value = aws_route53_record.web_backend.name
}

output "alb_target_group_arn" {
  value = aws_lb_target_group.web_lb_tgt_grp.arn
}
