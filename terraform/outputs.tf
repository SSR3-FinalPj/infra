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
