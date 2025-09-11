#!/bin/bash

# ============================================
# DNS Records Setup Script for ALB Endpoints
# ============================================
# 이 스크립트는 Kubernetes ALB Ingress가 생성된 후
# Route 53에 DNS 레코드를 자동으로 생성합니다.
#
# 사용법:
#   ./setup-dns-records.sh [domain_name]
#
# 예시:
#   ./setup-dns-records.sh meaire.store
# ============================================

set -e  # 에러 발생 시 스크립트 중단

# ============================================
# 설정 변수
# ============================================
DOMAIN_NAME=${1:-"meaire.store"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/dns-records-$$"

# 색상 출력을 위한 함수
print_info() {
    echo -e "\033[36m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

# ============================================
# 전제 조건 확인
# ============================================
check_prerequisites() {
    print_info "전제 조건 확인 중..."
    
    # kubectl 명령 확인
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl 명령을 찾을 수 없습니다. Kubernetes CLI를 설치해주세요."
        exit 1
    fi
    
    # AWS CLI 확인
    if ! command -v aws &> /dev/null; then
        print_error "aws 명령을 찾을 수 없습니다. AWS CLI를 설치해주세요."
        exit 1
    fi
    
    # AWS 인증 확인
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS 인증이 설정되지 않았습니다. 'aws configure'를 실행해주세요."
        exit 1
    fi
    
    print_success "전제 조건 확인 완료"
}

# ============================================
# Route 53 호스팅 영역 ID 조회
# ============================================
get_hosted_zone_id() {
    print_info "Route 53 호스팅 영역 ID 조회 중..."
    
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
        --output text | sed 's|/hostedzone/||')
    
    if [[ -z "$HOSTED_ZONE_ID" ]]; then
        print_error "도메인 '${DOMAIN_NAME}'의 Route 53 호스팅 영역을 찾을 수 없습니다."
        print_info "terraform apply를 먼저 실행했는지 확인해주세요."
        exit 1
    fi
    
    print_success "호스팅 영역 ID: $HOSTED_ZONE_ID"
}

# ============================================
# ALB 정보 조회
# ============================================
get_alb_info() {
    print_info "ALB 정보 조회 중..."
    
    # External ALB 정보 조회
    EXTERNAL_ALB_DNS=$(kubectl get ingress external-ingress -n dev-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [[ -z "$EXTERNAL_ALB_DNS" ]]; then
        print_error "External ingress ALB를 찾을 수 없습니다."
        print_info "kubectl get ingress -A 명령으로 ingress 상태를 확인해주세요."
        exit 1
    fi
    
    # Backend ALB 정보 조회
    BACKEND_ALB_DNS=$(kubectl get ingress backend-ingress -n dev-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [[ -z "$BACKEND_ALB_DNS" ]]; then
        print_error "Backend ingress ALB를 찾을 수 없습니다."
        exit 1
    fi
    
    # ALB 이름 추출 (ALB Hosted Zone ID 조회용)
    EXTERNAL_ALB_NAME=$(echo $EXTERNAL_ALB_DNS | cut -d'-' -f1-4)
    BACKEND_ALB_NAME=$(echo $BACKEND_ALB_DNS | cut -d'-' -f1-4)
    
    # ALB Hosted Zone ID 조회 (us-east-2 리전의 ALB는 모두 동일)
    ALB_HOSTED_ZONE_ID="Z3AADJGX6KTTL2"
    
    print_success "External ALB: $EXTERNAL_ALB_DNS"
    print_success "Backend ALB: $BACKEND_ALB_DNS"
    print_success "ALB Hosted Zone ID: $ALB_HOSTED_ZONE_ID"
}

# ============================================
# 기존 DNS 레코드 확인
# ============================================
check_existing_records() {
    print_info "기존 DNS 레코드 확인 중..."
    
    # front 서브도메인 확인
    EXISTING_FRONT=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='front.${DOMAIN_NAME}.'].Name" \
        --output text 2>/dev/null || echo "")
    
    # api 서브도메인 확인  
    EXISTING_API=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='api.${DOMAIN_NAME}.'].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_FRONT" ]]; then
        print_warning "front.${DOMAIN_NAME} 레코드가 이미 존재합니다."
        ACTION_FRONT="UPSERT"
    else
        ACTION_FRONT="CREATE"
    fi
    
    if [[ -n "$EXISTING_API" ]]; then
        print_warning "api.${DOMAIN_NAME} 레코드가 이미 존재합니다."
        ACTION_API="UPSERT"
    else
        ACTION_API="CREATE"
    fi
}

# ============================================
# Route 53 변경 배치 파일 생성
# ============================================
create_change_batch() {
    print_info "Route 53 변경 배치 파일 생성 중..."
    
    mkdir -p "$TEMP_DIR"
    
    cat > "${TEMP_DIR}/change-batch.json" << EOF
{
  "Comment": "Auto-generated DNS records for ALB endpoints - $(date)",
  "Changes": [
    {
      "Action": "${ACTION_FRONT}",
      "ResourceRecordSet": {
        "Name": "front.${DOMAIN_NAME}",
        "Type": "A",
        "AliasTarget": {
          "DNSName": "${EXTERNAL_ALB_DNS}",
          "EvaluateTargetHealth": true,
          "HostedZoneId": "${ALB_HOSTED_ZONE_ID}"
        }
      }
    },
    {
      "Action": "${ACTION_API}",
      "ResourceRecordSet": {
        "Name": "api.${DOMAIN_NAME}",
        "Type": "A",
        "AliasTarget": {
          "DNSName": "${BACKEND_ALB_DNS}",
          "EvaluateTargetHealth": true,
          "HostedZoneId": "${ALB_HOSTED_ZONE_ID}"
        }
      }
    }
  ]
}
EOF
    
    print_success "변경 배치 파일 생성 완료: ${TEMP_DIR}/change-batch.json"
}

# ============================================
# DNS 레코드 생성/업데이트
# ============================================
update_dns_records() {
    print_info "DNS 레코드 생성/업데이트 중..."
    
    CHANGE_INFO=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "file://${TEMP_DIR}/change-batch.json")
    
    CHANGE_ID=$(echo "$CHANGE_INFO" | jq -r '.ChangeInfo.Id')
    
    print_success "DNS 변경 요청 완료"
    print_info "변경 ID: $CHANGE_ID"
    
    # 변경 완료 대기 (선택적)
    print_info "DNS 변경 전파 대기 중... (최대 5분)"
    
    if aws route53 wait resource-record-sets-changed --id "$CHANGE_ID" --cli-read-timeout 300; then
        print_success "DNS 변경이 완료되었습니다!"
    else
        print_warning "DNS 변경 대기 시간이 초과되었지만, 백그라운드에서 계속 진행됩니다."
    fi
}

# ============================================
# DNS 해결 테스트
# ============================================
test_dns_resolution() {
    print_info "DNS 해결 테스트 중..."
    
    sleep 10  # DNS 전파를 위한 잠시 대기
    
    # front 서브도메인 테스트
    if nslookup "front.${DOMAIN_NAME}" 8.8.8.8 &> /dev/null; then
        print_success "front.${DOMAIN_NAME} DNS 해결 성공"
    else
        print_warning "front.${DOMAIN_NAME} DNS 해결 실패 (전파 중일 수 있음)"
    fi
    
    # api 서브도메인 테스트  
    if nslookup "api.${DOMAIN_NAME}" 8.8.8.8 &> /dev/null; then
        print_success "api.${DOMAIN_NAME} DNS 해결 성공"
    else
        print_warning "api.${DOMAIN_NAME} DNS 해결 실패 (전파 중일 수 있음)"
    fi
}

# ============================================
# 정리
# ============================================
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        print_info "임시 파일 정리 완료"
    fi
}

# ============================================
# 메인 실행
# ============================================
main() {
    print_info "DNS 레코드 설정 스크립트 시작"
    print_info "도메인: $DOMAIN_NAME"
    echo
    
    # 인터럽트 발생 시 정리
    trap cleanup EXIT
    
    check_prerequisites
    get_hosted_zone_id
    get_alb_info
    check_existing_records
    create_change_batch
    update_dns_records
    test_dns_resolution
    
    echo
    print_success "=== DNS 설정 완료 ==="
    print_info "이제 다음 주소로 접속할 수 있습니다:"
    print_info "  - https://front.${DOMAIN_NAME}"
    print_info "  - https://api.${DOMAIN_NAME}"
    echo
    print_info "SSL 인증서: ACM 자동 관리"
    print_info "HTTP → HTTPS 자동 리다이렉트 활성화"
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi