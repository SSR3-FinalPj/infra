[English](./SECURITY.md) | [한국어](./SECURITY.ko.md) | [日本語](./SECURITY.ja.md)

---

# 보안 설정 가이드 (Security Configuration Guide)

이 문서는 프로젝트의 민감한 정보를 **Ansible Vault**와 **Terraform tfvars**를 사용하여 안전하게 관리하는 방법을 설명합니다.

## 🔒 보안 원칙

1. **민감한 정보는 절대 Git에 커밋하지 않습니다**
2. **Ansible Vault로 암호화된 보안 관리를 사용합니다**
3. **환경별로 분리된 설정 파일을 사용합니다**
4. **실무 Best Practice를 준수합니다**

## 📁 파일 구조

```
refactored/
├── .gitignore                           # 민감한 파일들 제외
├── terraform/
│   ├── terraform.tfvars                 # Terraform 실제 값 (Git 제외)
│   └── terraform.tfvars.example         # Terraform 템플릿 (Git 포함)
└── ansible/
    ├── .vault_pass                      # Vault 패스워드 파일 (Git 제외)
    └── group_vars/all/
        ├── vars.yml                     # 공개 가능한 변수 (Git 포함)
        ├── vault.yml                    # 암호화된 민감 정보 (Git 포함)
        └── vault.yml.example            # Vault 템플릿 (Git 포함)
```

## 🚀 초기 설정

### 1단계: Terraform 설정

```bash
# Terraform 디렉토리로 이동
cd terraform

# 템플릿 파일 복사
cp terraform.tfvars.example terraform.tfvars

# 실제 값으로 수정
vi terraform.tfvars
```

**terraform.tfvars에서 수정해야 할 값들:**

- `YOUR_AWS_ACCOUNT_ID`: 실제 AWS 계정 ID (12자리)
- `YOUR_USERNAME`: 실제 IAM 사용자명

### 2단계: Ansible Vault 설정

```bash
# Ansible 디렉토리로 이동
cd ansible

# Vault 패스워드 파일 생성
echo "your_vault_password" > .vault_pass
chmod 600 .vault_pass

# Vault 파일 설정
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vi group_vars/all/vault.yml

# Vault 파일 암호화 (중요!)
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass
```

**group_vars/all/vault.yml에서 수정해야 할 값들:**

- 모든 패스워드들을 강력한 패스워드로 변경
- API 키들을 실제 발급받은 키로 교체
- 암호화 전에 실제 값들로 교체 필수!

## 🔐 Ansible Vault 사용법 (고급)

### Vault 파일 암호화

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### Vault 파일 편집

```bash
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Vault와 함께 플레이북 실행

```bash
# 패스워드 프롬프트 방식
ansible-playbook playbook.yml --ask-vault-pass --extra-vars "@terraform_outputs.json"

# 패스워드 파일 사용 (권장)
ansible-playbook playbook.yml --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"

# 특정 role만 실행
ansible-playbook playbook.yml --tags "airflow" --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"
```

## 🛠️ 배포 워크플로

### 전체 배포

```bash
# 1. Terraform으로 인프라 배포
cd terraform
terraform init
terraform apply

# 2. Terraform 출력값 저장
terraform output -json > ../ansible/terraform_outputs.json

# 3. Ansible로 애플리케이션 배포 (Vault 사용)
cd ../ansible
ansible-playbook playbook.yml --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"
```

### 환경변수 우선순위

Ansible에서는 다음 우선순위로 변수를 읽습니다:

1. **환경변수** (`.env` 파일): `lookup('env', 'VARIABLE_NAME')`
2. **Vault 변수** (암호화된 값): `vault_variable_name`
3. **기본값**: 없음 (오류 발생)

## ⚠️ 주의사항

### DO ✅

- 템플릿 파일(`.example`)은 Git에 커밋
- 강력한 패스워드 사용 (최소 12자, 특수문자 포함)
- 정기적인 패스워드 변경
- 프로덕션에서는 AWS Secrets Manager, HashiCorp Vault 등 사용

### DON'T ❌

- 실제 설정 파일(`.tfvars`, `.env`)을 Git에 커밋
- 약한 패스워드 사용 ('example', 'password123' 등)
- 실제 API 키를 코드나 문서에 하드코딩
- 팀원 간 Slack/이메일로 민감한 정보 공유

## 🔍 Git 커밋 전 체크리스트

커밋하기 전에 반드시 확인하세요:

```bash
# 민감한 파일들이 제외되었는지 확인
git status

# .gitignore가 제대로 동작하는지 확인
git check-ignore terraform/terraform.tfvars
git check-ignore ansible/.env

# 민감한 정보가 포함된 파일이 없는지 확인
git diff --cached | grep -E "(password|secret|key|token|arn:aws:iam::[0-9]+)"
```

## 🆘 문제 해결

### 문제: Terraform에서 변수 값이 없다고 오류

**해결책**: `terraform.tfvars` 파일이 존재하고 필수 변수들이 설정되었는지 확인

### 문제: Ansible에서 변수를 찾을 수 없음

**해결책**: `.env` 파일이 `ansible/` 디렉토리에 있는지, 변수명이 정확한지 확인

### 문제: API 키가 작동하지 않음

**해결책**:

1. API 키가 유효한지 확인
2. API 키 권한이 적절히 설정되었는지 확인
3. Rate limiting이나 quota 제한이 있는지 확인

## 📞 지원

문제가 발생하면 다음을 확인하세요:

1. 이 문서의 설정 단계를 모두 완료했는지
2. `.gitignore`에서 민감한 파일들이 제외되었는지
3. 환경변수 파일의 문법이 올바른지

---

**⚠️ 중요**: 이 프로젝트의 보안은 사용자의 책임입니다. 민감한 정보 관리에 각별히 주의하세요!
