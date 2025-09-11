# DNS Management Scripts

이 디렉토리는 ALB Ingress 배포 후 DNS 레코드를 자동으로 관리하는 스크립트들을 포함합니다.

## 배경

**왜 별도 스크립트가 필요한가?**

1. **배포 순서**: Terraform → Ansible → DNS 설정
2. **의존성 문제**: Terraform 단계에서는 ALB가 아직 생성되지 않음
3. **멱등성**: 생성/삭제 스크립트 세트로 일관성 보장

## 스크립트 목록

### 1. setup-dns-records.sh
ALB 생성 후 Route 53에 DNS A 레코드(ALIAS)를 자동 생성합니다.

**기능:**
- Kubernetes에서 ALB DNS 정보 자동 감지
- Route 53 호스팅 영역에 A 레코드 생성/업데이트
- DNS 전파 확인 및 테스트
- 멱등성 보장 (이미 존재하는 레코드는 UPSERT)

**사용법:**
```bash
# 기본 사용 (meaire.store 도메인)
./scripts/setup-dns-records.sh

# 다른 도메인 지정
./scripts/setup-dns-records.sh example.com
```

### 2. cleanup-dns-records.sh
terraform destroy 전에 DNS 레코드를 깔끔하게 정리합니다.

**기능:**
- 생성된 DNS A 레코드 자동 탐지
- 안전한 삭제 확인 프롬프트
- Route 53에서 레코드 삭제
- 삭제 확인 및 검증

**사용법:**
```bash
# 기본 사용 (확인 프롬프트 포함)
./scripts/cleanup-dns-records.sh

# 강제 실행 (확인 생략)
./scripts/cleanup-dns-records.sh meaire.store --force
```

## 전체 배포 워크플로우

### 1. 초기 배포
```bash
# 1. Terraform으로 인프라 생성
cd terraform
terraform init
terraform apply

# 2. Ansible로 애플리케이션 배포
cd ../ansible
terraform output -json > terraform_outputs.json
ansible-playbook playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# 3. DNS 레코드 설정
cd ../scripts
./setup-dns-records.sh meaire.store
```

### 2. 정리 (삭제)
```bash
# 1. DNS 레코드 정리 (중요!)
cd scripts
./cleanup-dns-records.sh meaire.store

# 2. Terraform으로 인프라 삭제
cd ../terraform
terraform destroy
```

## 생성되는 DNS 레코드

| 도메인 | 타입 | 대상 |
|--------|------|------|
| `front.{domain}` | A (ALIAS) | External ALB DNS |
| `api.{domain}` | A (ALIAS) | Backend ALB DNS |

## 전제 조건

### 시스템 요구사항
- AWS CLI 설치 및 인증 설정
- kubectl 설치 및 EKS 클러스터 접근 권한
- jq 설치 (JSON 파싱용, 선택사항)

### AWS 권한
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets",
                "route53:GetChange"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeLoadBalancers"
            ],
            "Resource": "*"
        }
    ]
}
```

### Kubernetes 권한
```bash
# EKS 클러스터 접근 설정
aws eks update-kubeconfig --region us-east-2 --name my-eks-cluster

# Ingress 조회 권한 확인
kubectl get ingress -A
```

## 문제 해결

### 일반적인 오류

**1. "호스팅 영역을 찾을 수 없습니다"**
```bash
# Terraform이 완료되었는지 확인
terraform show | grep route53_zone

# AWS CLI 인증 확인
aws sts get-caller-identity
```

**2. "ALB를 찾을 수 없습니다"**
```bash
# Ingress 상태 확인
kubectl get ingress -A

# ALB Controller 로그 확인
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**3. "DNS 해결 실패"**
```bash
# DNS 전파 확인 (최대 15분 소요)
nslookup front.meaire.store 8.8.8.8

# Route 53 레코드 확인
aws route53 list-resource-record-sets --hosted-zone-id Z084298012T7X20LDQK1P
```

### 스크립트 디버깅

**verbose 모드 실행:**
```bash
# bash 디버그 모드
bash -x ./setup-dns-records.sh

# 개별 단계 확인
kubectl get ingress -A
aws route53 list-hosted-zones
```

## 보안 고려사항

1. **스크립트 권한**: 실행 권한만 부여 (`chmod +x`)
2. **AWS 인증**: IAM 역할 사용 권장 (하드코딩된 키 금지)
3. **확인 프롬프트**: 삭제 작업 시 사용자 확인 필수
4. **임시 파일**: 실행 후 자동 정리 (`/tmp` 디렉토리 사용)

## 향후 개선 방안

### 1. Ansible Integration
```yaml
# ansible/roles/dns-management/tasks/main.yml
- name: Setup DNS records for ALB
  script: ../../scripts/setup-dns-records.sh {{ domain_name }}
  delegate_to: localhost
```

### 2. Terraform Null Resource
```hcl
resource "null_resource" "dns_setup" {
  provisioner "local-exec" {
    command = "${path.module}/../scripts/setup-dns-records.sh ${var.domain_name}"
  }
  
  depends_on = [aws_acm_certificate_validation.main]
}
```

### 3. GitHub Actions Integration
```yaml
- name: Setup DNS Records
  run: |
    chmod +x ./scripts/setup-dns-records.sh
    ./scripts/setup-dns-records.sh ${{ env.DOMAIN_NAME }}
```

## 라이선스

이 스크립트들은 프로젝트의 라이선스를 따릅니다.