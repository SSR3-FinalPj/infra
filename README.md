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

## 3. 배포 절차

배포는 두 단계로 진행됩니다. 먼저 Terraform으로 AWS 인프라를 생성한 후, Ansible로 해당 인프라 위에 애플리케이션을 배포합니다.

### 1단계: Terraform으로 AWS 인프라 배포

1.  **Terraform 작업 디렉토리로 이동합니다.**

    ```bash
    cd refactored/terraform
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
    # (현재 위치: refactored/terraform)
    terraform output -json > ../ansible/terraform_outputs.json
    ```

2.  **Ansible 작업 디렉토리로 이동합니다.**

    ```bash
    # (현재 위치: refactored/terraform)
    cd ../ansible
    ```

3.  **Ansible 플레이북을 실행하여 애플리케이션을 배포합니다.**
    `--extra-vars` 옵션을 사용하여 방금 생성한 JSON 파일의 내용을 변수로 전달합니다.
    ```bash
    # (현재 위치: refactored/ansible)
    ansible-playbook playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```
    플레이북이 실행되면서 `csi-drivers` Role부터 `ingress` Role까지 정의된 순서대로 모든 애플리케이션이 클러스터에 배포됩니다.

### 특정 애플리케이션만 배포

특정 태그를 사용하여 개별 애플리케이션만 배포할 수 있습니다:

```bash
# Prometheus 모니터링 스택만 배포
ansible-playbook playbook.yml --tags "prometheus" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Kafka와 Zookeeper만 배포
ansible-playbook playbook.yml --tags "kafka,zookeeper" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
```

## 4. 리소스 삭제 절차

생성된 모든 리소스를 삭제하려면 배포의 역순으로 진행합니다.

1.  **Ansible로 애플리케이션 삭제:**

    ```bash
    ansible-playbook delete_playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```

2.  **Terraform으로 인프라 전체 삭제:**
    `terraform` 디렉토리에서 `destroy` 명령을 실행하면 VPC부터 EKS 클러스터까지 모든 AWS 리소스가 삭제됩니다. 엔드포인트 대상 네트워크 연결도 해제해 줄 것.
    ec2 -> 볼륨도 제거, VPC 안 지워지면 손으로 삭제
    ```bash
    cd refactored/terraform
    terraform destroy
    ```
    `yes`를 입력하여 삭제를 진행합니다.

## 5. 배포되는 애플리케이션 스택

애플리케이션은 `ansible/playbook.yml`을 통해 다음 순서로 배포됩니다:

### 🏗️ **인프라 레이어**

1. **CSI Drivers**: EFS 및 EBS 볼륨 지원
2. **ALB Controller**: AWS Application Load Balancer 관리
3. **Storage**: StorageClass 및 PersistentVolume 설정

### 🌐 **네트워킹 레이어**

4. **Ingress**: ALB 기반 외부/내부 로드밸런서 설정

### 💾 **데이터 레이어**

5. **Zookeeper**: 분산 시스템 코디네이션
6. **Kafka**: 실시간 스트리밍 플랫폼 (+Kafka UI)
7. **PostgreSQL**: 관계형 데이터베이스 (Airflow용)

### ⚙️ **처리 레이어**

8. **Airflow**: 워크플로우 오케스트레이션 (커스텀 DAG 포함)
9. **Adminer**: 데이터베이스 관리 도구

### 🚀 **캐싱 레이어**

10. **Redis**: 인메모리 캐시 (Sentinel 구성)

### 📊 **분석 레이어**

11. **Elasticsearch**: 검색 및 분석 엔진
12. **Kibana**: 데이터 시각화 도구
13. **Elastic-HQ**: Elasticsearch 클러스터 관리

### 📈 **모니터링 레이어** (Helm 차트)

14. **Prometheus Stack**: Helm을 사용하여 통합 배포
    - **Prometheus**: 메트릭 수집 및 저장
    - **Grafana**: 대시보드 및 시각화
    - **AlertManager**: 알림 관리
    - 네임스페이스: `dev-system`
    - ServiceMonitor를 통한 기존 서비스 메트릭 수집

### 🔧 **관리 레이어**

15. **Portainer**: Docker/Kubernetes 관리 인터페이스

### 🗄️ **추가 데이터베이스**

16. **MySQL**: 범용 관계형 데이터베이스

### 📋 **애플리케이션**

17. **Redmine**: 프로젝트 관리 도구

### 📝 **모니터링 접근 정보**

- **Grafana**: ALB Internal Ingress를 통해 접근 가능
- **Prometheus**: `http://monitoring-kube-prometheus-prometheus.dev-system:9090`
- **AlertManager**: `http://monitoring-kube-prometheus-alertmanager.dev-system:9093`

## 6. 프로젝트 구조

- **`terraform/`**: 모든 AWS 인프라(VPC, EKS, EFS, IAM, Addons) 정의
- **`ansible/`**: 모든 Kubernetes 리소스(애플리케이션) 배포 정의
  - `inventory/`: Ansible이 대상으로 할 서버 목록 (현재는 `localhost`)
  - `roles/`: 각 애플리케이션별로 분리된 Role 디렉토리
  - `playbook.yml`: Role 실행 순서를 정의하는 메인 플레이북
  - `terraform_outputs.json`: Terraform에서 생성된 출력 값이 저장되는 파일 (Git에는 포함하지 않는 것을 권장)
- **`temp_airflow/`**: 커스텀 Airflow 설정 및 DAG
