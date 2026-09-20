output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main_eks_cluster.name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster"
  value       = aws_eks_cluster.main_eks_cluster.endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL, needed for IRSA"
  value       = aws_eks_cluster.main_eks_cluster.identity[0].oidc[0].issuer
}

output "ecr_repository_url" {
  description = "URL of the application ECR repository"
  value       = aws_ecr_repository.ecr_app.repository_url
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.main_eks_node_group.node_group_name
}

output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = "http://${aws_eip.eip_jenkins_master[0].public_ip}:8080"
}

output "jenkins_public_ip" {
  description = "Public IP of the Jenkins master"
  value       = aws_eip.eip_jenkins_master[0].public_ip
}

output "update_kubeconfig_command" {
  description = "Run this to point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main_eks_cluster.name}"
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main_vpc.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnet[*].id
}

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}