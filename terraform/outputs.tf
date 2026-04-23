output "app_instance_1_ip" {
  value = module.ec2_app.elastic_ips[0]
}

output "app_instance_2_ip" {
  value = module.ec2_app.elastic_ips[1]
}

output "mongo_private_ip" {
  value = module.ec2_db.private_ip
}

output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "DNS name of the ALB — use this to access the application in the browser"
}

output "ecr_backend_url" {
  value = module.ecr.repository_urls["backend"]
}

output "ecr_frontend_url" {
  value = module.ecr.repository_urls["frontend"]
}

output "github_actions_role_arn" {
  value       = module.iam.github_actions_role_arn
  description = "IAM role ARN for GitHub Actions OIDC — stored as AWS_ROLE_ARN secret by build-infra.sh"
}
