############################################
# variables.tf
############################################

# 사용할 AWS 리전을 정의
variable "aws_region" {
  description = "AWS region"
  type        = string
}

# EKS 클러스터 이름 설정
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

# 쿠버네티스 버전 (예: 1.33)
variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
}

/*
왜 string?
1.33은 쿠버네티스 버전이지만 숫자가 아닌 문자열로 사용되어야 하기 때문
Terraform에서는 버전, 경로, 리전 이름, 클러스터 이름 등은 보통 string 타입으로 취급
*/

# EKS 워커 노드의 EC2 인스턴스 타입
variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
}

# EKS Node Group의 스케일링 기본/최대/최소 수를 지정
variable "desired_node_capacity" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
}

variable "max_node_capacity" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
}

variable "min_node_capacity" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
}

# EKS 클러스터에 Admin 접근 권한을 부여할 대상 사용자 (ex. aws-auth에 추가될 사용자 ARN)
variable "target_iam_user_arn" {
  description = "ARN of the IAM user to grant EKS cluster admin access"
  type        = string
}

# EKS 클러스터 접근 권한을 부여할 IAM principals 목록
variable "target_iam_principals_arn" {
  description = "List of IAM principal ARNs to grant EKS cluster access"
  type        = list(string)
}
