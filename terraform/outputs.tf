############################################
# outputs.tf
############################################

output "eks_cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "The CA data for the EKS cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs."
  value       = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs."
  value       = values(aws_subnet.private)[*].id
}

output "efs_file_system_id" {
  description = "The ID of the EFS file system."
  value       = aws_efs_file_system.main.id
}

output "efs_access_point_ids" {
  description = "A map of EFS access point names to their IDs."
  value       = { for k, v in aws_efs_access_point.main : k => v.id }
}

output "efs_csi_driver_role_arn" {
  description = "The ARN of the IAM role for the EFS CSI driver."
  value       = aws_iam_role.efs_csi_driver_role.arn
}

output "ebs_csi_driver_role_arn" {
  description = "The ARN of the IAM role for the EBS CSI driver."
  value       = aws_iam_role.ebs_csi_driver_role.arn
}

output "alb_controller_role_arn" {
  description = "The ARN of the IAM role for the ALB controller."
  value       = aws_iam_role.alb_controller_role.arn
}

output "aws_region" {
  description = "The AWS region where the infrastructure is deployed."
  value       = var.aws_region
}

output "domain_name" {
  description = "The domain name for SSL certificates."
  value       = var.domain_name
}

# ============================================
# ACM (Amazon Certificate Manager) Outputs
# ============================================

output "acm_certificate_arn" {
  description = "The ARN of the ACM certificate"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "route53_zone_id" {
  description = "The Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_zone_name_servers" {
  description = "The Route 53 name servers for the hosted zone"
  value       = aws_route53_zone.main.name_servers
}

output "route53_zone_name" {
  description = "The Route 53 hosted zone name"
  value       = aws_route53_zone.main.name
}

