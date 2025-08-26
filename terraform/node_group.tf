############################################
# node_group.tf
############################################

# EC2 Node Role 정의
resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

# 필수 정책들
resource "aws_iam_role_policy_attachment" "eks_node_policy_attach_1" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_policy_attach_2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_policy_attach_3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}


# NodeGroup 생성 (역할별 분리)

# 1. Master Node Group (ES, Spark)
resource "aws_eks_node_group" "master_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-master"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = values(aws_subnet.private)[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  

  labels = {
    "dspESType"    = "master"
    "dspSparkType" = "master"
  }

  tags = {
    Name = "${var.cluster_name}-nodegroup-master"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node_policy_attach_1]
}

# 2. Data1 Node Group (ES, Spark)
resource "aws_eks_node_group" "data1_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-data1"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = values(aws_subnet.private)[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  

  labels = {
    "dspESType"    = "data1"
    "dspSparkType" = "worker"
  }

  tags = {
    Name = "${var.cluster_name}-nodegroup-data1"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node_policy_attach_1]
}

# 3. Data2 Node Group (ES, Spark, DB)
resource "aws_eks_node_group" "data2_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-data2"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = values(aws_subnet.private)[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  

  labels = {
    "dspESType"    = "data2"
    "dspSparkType" = "worker"
    "dspDBType"    = "postgre"
  }

  tags = {
    Name = "${var.cluster_name}-nodegroup-data2"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node_policy_attach_1]
}
