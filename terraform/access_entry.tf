############################################
# access_entry.tf
############################################

resource "aws_eks_access_entry" "cluster_access" {
  for_each      = toset(var.target_iam_principals_arn) # 각 ARN에 대해 리소스 생성
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value # 리스트의 각 ARN 사용
  kubernetes_groups = ["eks-admin-group"]
  # access_entry_name은 지정하지 않으면 자동으로 생성됩니다.
  # 필요하다면 access_entry_name = replace(split("/", each.value)[length(split("/", each.value)) - 1], "-", "_") 와 같이 동적으로 생성 가능
}

resource "aws_eks_access_policy_association" "cluster_admin_policy" {
  for_each      = aws_eks_access_entry.cluster_access # 위에서 생성된 각 Access Entry에 대해 정책 연결
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn # Access Entry의 principal_arn 참조
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # 관리자 정책
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_access]
}

