# EKS 클러스터 및 애플리케이션 스택 배포 자동화 (Terraform & Ansible)

## 1. 개요

이 프로젝트는 AWS EKS 클러스터와 그 위에서 동작하는 전체 애플리케이션 스택을 IaC(Infrastructure as Code) 원칙에 따라 배포하고 관리합니다.

기존의 쉘 스크립트 기반 배포 방식을 리팩토링하여, AWS 인프라 프로비저닝은 **Terraform**으로, Kubernetes 클러스터 설정 및 애플리케이션 배포는 **Ansible**로 역할을 명확히 분리했습니다. 이를 통해 전체 배포 과정의 자동화 수준과 안정성, 재사용성을 높였습니다.

- **Terraform (`terraform/`):** VPC, Subnet, EKS 클러스터, Node Groups, EFS, IAM Role 및 Policy, 클러스터 애드온(ALB Controller, CSI Drivers) 등 모든 AWS 리소스를 관리합니다.
- **Ansible (`ansible/`):** Terraform으로 프로비저닝된 EKS 클러스터 위에 애플리케이션(Zookeeper, Kafka, Databases, 모니터링 스택, Redmine 등)을 Role 기반으로 체계적으로 배포합니다.

## 2. 사전 요구사항

이 프로젝트를 실행하기 위해 로컬 머신에 다음 도구들이 설치 및 설정되어 있어야 합니다.

- **Terraform** (v1.0 이상 권장)
- **Ansible** (v2.10 이상 권장)
  - `community.kubernetes` 컬렉션 설치: `ansible-galaxy collection install community.kubernetes`
- **AWS CLI**
  - AWS 자격 증명(Access Key, Secret Key)이 설정되어 있어야 합니다. (`aws configure`)
- **kubectl**
- **Helm** (v3.0 이상 권장)
  - Prometheus 모니터링 스택 배포에 필요합니다.

### ⚠️ 보안 설정 (중요!)

배포하기 전에 반드시 **[SECURITY.md](SECURITY.md)** 문서를 참고하여 환경변수를 설정하세요:

1. **Terraform 설정**: `cp terraform/terraform.tfvars.example terraform/terraform.tfvars`
2. **Ansible 설정**: `cp ansible/.env.example ansible/.env`
3. 실제 AWS 계정 정보와 강력한 패스워드로 수정

## 3. 배포 절차

배포는 두 단계로 진행됩니다. 먼저 Terraform으로 AWS 인프라를 생성한 후, Ansible로 해당 인프라 위에 애플리케이션을 배포합니다.

### 1단계: Terraform으로 AWS 인프라 배포

1.  **Terraform 작업 디렉토리로 이동합니다.**

    ```bash
    cd terraform
    ```

2.  **Terraform을 초기화합니다.**

    ```bash
    terraform init
    ```

3.  **Terraform 계획을 확인하고 인프라를 배포합니다.**
    `apply` 명령을 실행하면 생성될 리소스 목록이 표시됩니다. `yes`를 입력하여 배포를 진행합니다.

    ```bash
    terraform apply
    ```

    이 과정은 EKS 클러스터 생성으로 인해 약 15~20분 정도 소요될 수 있습니다.

4.  **배포 완료 후 출력(Output) 값을 확인합니다.**
    배포가 성공적으로 완료되면 `outputs.tf`에 정의된 값들(VPC ID, Subnet ID, EFS ID 등)이 화면에 출력됩니다. 이 값들은 다음 Ansible 단계에서 사용됩니다.

5.  **Kubeconfig 설정:**
    `apply`가 완료된 후, 다음 명령을 실행하여 로컬 `kubectl`이 EKS 클러스터와 통신할 수 있도록 설정합니다. Terraform 출력값을 확인하여 정확한 클러스터 이름과 리전을 입력하세요.
    ```bash
    aws eks update-kubeconfig --region <aws_region> --name <cluster_name>
    ```

### 2단계: Ansible로 애플리케이션 배포

1.  **Terraform 출력 값을 파일로 저장합니다.**
    Ansible에서 변수로 사용하기 위해, `terraform` 디렉토리에서 다음 명령을 실행하여 출력 값을 JSON 파일로 저장합니다.

    ```bash
    # (현재 위치: terraform)
    terraform output -json > ../ansible/terraform_outputs.json
    ```

2.  **Ansible 작업 디렉토리로 이동합니다.**

    ```bash
    # (현재 위치: terraform)
    cd ../ansible
    ```

3.  **Ansible 플레이북을 실행하여 애플리케이션을 배포합니다.**
    `--extra-vars` 옵션을 사용하여 방금 생성한 JSON 파일의 내용을 변수로 전달합니다.
    ```bash
    # (현재 위치: ansible)
    # 애플리케이션 배포
    ansible-playbook playbook.yml -e "state=present" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```
    **참고**: `state=present`는 기본값이므로 생략 가능하지만, 명시적 표현을 위해 권장합니다.
    플레이북이 실행되면서 `csi-drivers` Role부터 `ingress` Role까지 정의된 순서대로 모든 애플리케이션이 클러스터에 배포됩니다.

### 특정 애플리케이션만 배포

특정 태그를 사용하여 개별 애플리케이션만 배포할 수 있습니다:

```bash
# Elasticsearch와 Kibana만 배포
ansible-playbook playbook.yml -e "state=present" --tags "elasticsearch,kibana" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Kafka와 Zookeeper만 배포
ansible-playbook playbook.yml -e "state=present" --tags "kafka,zookeeper" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Zipkin 트레이싱만 배포
ansible-playbook playbook.yml -e "state=present" --tags "zipkin" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
```

## 4. 리소스 삭제 절차 ⚡ **개선됨!**

**🎉 새로운 방식**: 이제 단일 플레이북으로 생성과 삭제를 모두 처리할 수 있습니다!

### **전체 리소스 삭제**

1.  **Ansible로 애플리케이션 삭제 (새로운 방식):**
    
    ```bash
    # 모든 애플리케이션을 의존성 역순으로 자동 삭제
    ansible-playbook playbook.yml -e "state=absent" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```
    
    **장점:**
    - ✅ 의존성 순서 자동 관리 (`ingress` → `portainer` → ... → `csi-drivers` 순서로 삭제)
    - ✅ 단일 파일로 생성/삭제 모두 처리 (DRY 원칙)
    - ✅ 기존 복잡한 `delete_playbook.yml` (337줄) 불필요

### **특정 애플리케이션만 삭제**

```bash
# 특정 서비스만 삭제
ansible-playbook playbook.yml -e "state=absent" --tags "mysql,redmine" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# 모니터링 스택만 삭제  
ansible-playbook playbook.yml -e "state=absent" --tags "prometheus,zipkin" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
```

2.  **Terraform으로 인프라 전체 삭제:**
    모든 애플리케이션 삭제 후 AWS 인프라를 정리합니다.
    ```bash
    cd terraform
    terraform destroy
    ```
    `yes`를 입력하여 삭제를 진행합니다.

### **~~기존 방식~~ (더 이상 필요 없음)**
~~`delete_playbook.yml`을 사용하던 기존 방식은 이제 불필요합니다.~~

## 📋 **통합 워크플로우 (권장)**

### **완전한 배포 사이클**
```bash
# 1. 인프라 생성
cd terraform
terraform init
terraform apply
terraform output -json > ../ansible/terraform_outputs.json

# 2. 애플리케이션 배포
cd ../ansible  
ansible-playbook playbook.yml -e "state=present" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# 3. DNS 설정 (선택사항)
cd ../scripts
./setup-dns-records.sh
```

### **완전한 정리 사이클**
```bash
# 1. 애플리케이션 삭제 (의존성 역순 자동 처리)
cd ansible
ansible-playbook playbook.yml -e "state=absent" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# 2. 인프라 삭제
cd ../terraform  
terraform destroy
```

### **부분 업데이트 사이클**
```bash
# 특정 서비스만 재배포
ansible-playbook playbook.yml -e "state=absent" --tags "mysql,redmine" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
ansible-playbook playbook.yml -e "state=present" --tags "mysql,redmine" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
```

## 5. 배포되는 애플리케이션 스택

애플리케이션은 `ansible/playbook.yml`을 통해 다음 순서로 배포됩니다:

### 🏗️ **인프라 레이어**

1. **CSI Drivers**: EFS 및 EBS 볼륨 지원
2. **ALB Controller**: AWS Application Load Balancer 관리
3. **Storage**: StorageClass 및 PersistentVolume 설정

### 💾 **데이터 레이어**

4. **Zookeeper**: 분산 시스템 코디네이션
5. **Kafka**: 실시간 스트리밍 플랫폼
6. **PostgreSQL**: 관계형 데이터베이스
7. **Redis**: 인메모리 캐시

### ⚙️ **관리 도구**

8. **Adminer**: 데이터베이스 관리 도구

### 📊 **검색 및 분석**

9. **Elasticsearch**: 검색 및 분석 엔진
10. **Kibana**: 데이터 시각화 도구
11. **Elastic-HQ**: Elasticsearch 클러스터 관리

### 📈 **모니터링 및 트레이싱**

12. **Zipkin**: 분산 트레이싱 시스템

### 🔧 **관리 인터페이스**

13. **Portainer**: Docker/Kubernetes 관리 인터페이스

### 🌐 **네트워킹**

14. **Ingress**: ALB 기반 로드밸런서 및 라우팅 설정

### 📋 **사용 가능하지만 비활성화된 역할**

- **Airflow**: 워크플로우 오케스트레이션 (역할 존재, playbook에서 제외)
- **MySQL**: 범용 관계형 데이터베이스 (역할 존재, playbook에서 제외)
- **Redmine**: 프로젝트 관리 도구 (역할 존재, playbook에서 제외)
- **Prometheus**: 메트릭 수집 시스템 (역할 존재, 현재 주석 처리됨)

## 6. 프로젝트 구조

- **`terraform/`**: 모든 AWS 인프라(VPC, EKS, EFS, IAM, Addons) 정의
- **`ansible/`**: 모든 Kubernetes 리소스(애플리케이션) 배포 정의
  - `inventory/`: Ansible이 대상으로 할 서버 목록 (현재는 `localhost`)
  - `roles/`: 각 애플리케이션별로 분리된 Role 디렉토리
  - `playbook.yml`: Role 실행 순서를 정의하는 메인 플레이북
  - `terraform_outputs.json`: Terraform에서 생성된 출력 값이 저장되는 파일 (Git에는 포함하지 않는 것을 권장)
- **`scripts/`**: DNS 레코드 관리 및 기타 유틸리티 스크립트
