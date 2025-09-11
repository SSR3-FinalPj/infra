#!/bin/bash

# ============================================
# DNS Records Cleanup Script for ALB Endpoints
# ============================================
# 이 스크립트는 setup-dns-records.sh로 생성된 DNS 레코드를
# 삭제하여 terraform destroy 전 깔끔한 정리를 수행합니다.
#
# 사용법:
#   ./cleanup-dns-records.sh [domain_name]
#
# 예시:
#   ./cleanup-dns-records.sh meaire.store
#
# 주의: terraform destroy 전에 실행하세요!
# ============================================

set -e  # 에러 발생 시 스크립트 중단

# ============================================
# 설정 변수
# ============================================
DOMAIN_NAME=${1:-"meaire.store"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/dns-cleanup-$$"

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
    
    # jq 명령 확인 (JSON 파싱용)
    if ! command -v jq &> /dev/null; then
        print_warning "jq 명령을 찾을 수 없습니다. JSON 파싱이 제한될 수 있습니다."
        print_info "Ubuntu/Debian: sudo apt-get install jq"
        print_info "CentOS/RHEL: sudo yum install jq"
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
        print_warning "도메인 '${DOMAIN_NAME}'의 Route 53 호스팅 영역을 찾을 수 없습니다."
        print_info "이미 삭제되었거나 존재하지 않는 것 같습니다."
        exit 0
    fi
    
    print_success "호스팅 영역 ID: $HOSTED_ZONE_ID"
}

# ============================================
# 기존 DNS 레코드 확인
# ============================================
find_existing_records() {
    print_info "삭제할 DNS 레코드 검색 중..."
    
    mkdir -p "$TEMP_DIR"
    
    # 호스팅 영역의 모든 레코드 조회
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --output json > "${TEMP_DIR}/all-records.json"
    
    # front 서브도메인 레코드 찾기
    FRONT_RECORD=$(jq -r ".ResourceRecordSets[] | select(.Name == \"front.${DOMAIN_NAME}.\") | select(.Type == \"A\")" "${TEMP_DIR}/all-records.json" 2>/dev/null || echo "null")
    
    # api 서브도메인 레코드 찾기
    API_RECORD=$(jq -r ".ResourceRecordSets[] | select(.Name == \"api.${DOMAIN_NAME}.\") | select(.Type == \"A\")" "${TEMP_DIR}/all-records.json" 2>/dev/null || echo "null")
    
    # 검색 결과 저장
    echo "$FRONT_RECORD" > "${TEMP_DIR}/front-record.json"
    echo "$API_RECORD" > "${TEMP_DIR}/api-record.json"
    
    # 삭제할 레코드 카운트
    RECORDS_TO_DELETE=0
    
    if [[ "$FRONT_RECORD" != "null" && -n "$FRONT_RECORD" ]]; then
        print_info "front.${DOMAIN_NAME} A 레코드 발견 (삭제 대상)"
        RECORDS_TO_DELETE=$((RECORDS_TO_DELETE + 1))
        HAS_FRONT_RECORD=true
    else
        print_info "front.${DOMAIN_NAME} A 레코드 없음"
        HAS_FRONT_RECORD=false
    fi
    
    if [[ "$API_RECORD" != "null" && -n "$API_RECORD" ]]; then
        print_info "api.${DOMAIN_NAME} A 레코드 발견 (삭제 대상)"
        RECORDS_TO_DELETE=$((RECORDS_TO_DELETE + 1))
        HAS_API_RECORD=true
    else
        print_info "api.${DOMAIN_NAME} A 레코드 없음"
        HAS_API_RECORD=false
    fi
    
    if [[ $RECORDS_TO_DELETE -eq 0 ]]; then
        print_success "삭제할 DNS 레코드가 없습니다. 정리 완료!"
        exit 0
    fi
    
    print_info "총 ${RECORDS_TO_DELETE}개의 레코드를 삭제합니다."
}

# ============================================
# 사용자 확인
# ============================================
confirm_deletion() {
    print_warning "다음 DNS 레코드들을 삭제하려고 합니다:"
    
    if [[ "$HAS_FRONT_RECORD" == true ]]; then
        echo "  - front.${DOMAIN_NAME} (A 레코드)"
    fi
    
    if [[ "$HAS_API_RECORD" == true ]]; then
        echo "  - api.${DOMAIN_NAME} (A 레코드)"
    fi
    
    echo
    print_warning "이 작업은 되돌릴 수 없습니다!"
    print_info "계속하려면 'yes'를 입력하세요:"
    
    read -p "> " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        print_info "사용자가 취소했습니다. 작업을 중단합니다."
        exit 0
    fi
}

# ============================================
# Route 53 변경 배치 파일 생성
# ============================================
create_deletion_batch() {
    print_info "삭제 배치 파일 생성 중..."
    
    # 변경 배치 시작
    cat > "${TEMP_DIR}/deletion-batch.json" << 'EOF'
{
  "Comment": "Auto-generated deletion of ALB DNS records",
  "Changes": [
EOF
    
    CHANGES_ADDED=0
    
    # front 레코드 삭제
    if [[ "$HAS_FRONT_RECORD" == true ]]; then
        if [[ $CHANGES_ADDED -gt 0 ]]; then
            echo "," >> "${TEMP_DIR}/deletion-batch.json"
        fi
        
        echo "    {" >> "${TEMP_DIR}/deletion-batch.json"
        echo "      \"Action\": \"DELETE\"," >> "${TEMP_DIR}/deletion-batch.json"
        echo "      \"ResourceRecordSet\":" >> "${TEMP_DIR}/deletion-batch.json"
        
        # 기존 레코드 정보를 그대로 사용 (DELETE는 정확한 매치 필요)
        cat "${TEMP_DIR}/front-record.json" | sed 's/^/      /' >> "${TEMP_DIR}/deletion-batch.json"
        
        echo "    }" >> "${TEMP_DIR}/deletion-batch.json"
        CHANGES_ADDED=$((CHANGES_ADDED + 1))
    fi
    
    # api 레코드 삭제
    if [[ "$HAS_API_RECORD" == true ]]; then
        if [[ $CHANGES_ADDED -gt 0 ]]; then
            echo "," >> "${TEMP_DIR}/deletion-batch.json"
        fi
        
        echo "    {" >> "${TEMP_DIR}/deletion-batch.json"
        echo "      \"Action\": \"DELETE\"," >> "${TEMP_DIR}/deletion-batch.json"
        echo "      \"ResourceRecordSet\":" >> "${TEMP_DIR}/deletion-batch.json"
        
        # 기존 레코드 정보를 그대로 사용
        cat "${TEMP_DIR}/api-record.json" | sed 's/^/      /' >> "${TEMP_DIR}/deletion-batch.json"
        
        echo "    }" >> "${TEMP_DIR}/deletion-batch.json"
        CHANGES_ADDED=$((CHANGES_ADDED + 1))
    fi
    
    # 변경 배치 종료
    cat >> "${TEMP_DIR}/deletion-batch.json" << 'EOF'
  ]
}
EOF
    
    print_success "삭제 배치 파일 생성 완료"
}

# ============================================
# DNS 레코드 삭제 실행
# ============================================
delete_dns_records() {
    print_info "DNS 레코드 삭제 실행 중..."
    
    CHANGE_INFO=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "file://${TEMP_DIR}/deletion-batch.json")
    
    CHANGE_ID=$(echo "$CHANGE_INFO" | jq -r '.ChangeInfo.Id' 2>/dev/null || echo "unknown")
    
    print_success "DNS 삭제 요청 완료"
    if [[ "$CHANGE_ID" != "unknown" ]]; then
        print_info "변경 ID: $CHANGE_ID"
    fi
    
    # 변경 완료 대기 (선택적)
    print_info "DNS 변경 전파 대기 중... (최대 3분)"
    
    if [[ "$CHANGE_ID" != "unknown" ]] && aws route53 wait resource-record-sets-changed --id "$CHANGE_ID" --cli-read-timeout 180 2>/dev/null; then
        print_success "DNS 레코드 삭제가 완료되었습니다!"
    else
        print_warning "DNS 변경 대기를 건너뛰었지만, 백그라운드에서 계속 진행됩니다."
    fi
}

# ============================================
# 삭제 확인
# ============================================
verify_deletion() {
    print_info "삭제 확인 중..."
    
    sleep 5  # DNS 전파를 위한 잠시 대기
    
    # front 서브도메인 확인
    if nslookup "front.${DOMAIN_NAME}" 8.8.8.8 &> /dev/null; then
        print_warning "front.${DOMAIN_NAME} 여전히 해결됨 (DNS 캐시 또는 전파 지연)"
    else
        print_success "front.${DOMAIN_NAME} 삭제 확인"
    fi
    
    # api 서브도메인 확인  
    if nslookup "api.${DOMAIN_NAME}" 8.8.8.8 &> /dev/null; then
        print_warning "api.${DOMAIN_NAME} 여전히 해결됨 (DNS 캐시 또는 전파 지연)"
    else
        print_success "api.${DOMAIN_NAME} 삭제 확인"
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
    print_info "DNS 레코드 정리 스크립트 시작"
    print_info "도메인: $DOMAIN_NAME"
    echo
    
    # 인터럽트 발생 시 정리
    trap cleanup EXIT
    
    check_prerequisites
    get_hosted_zone_id
    find_existing_records
    
    # 대화형 확인 (스크립트 인자로 스킵 가능)
    if [[ "$2" != "--force" ]]; then
        confirm_deletion
    else
        print_warning "--force 옵션으로 확인 과정을 건너뜁니다."
    fi
    
    create_deletion_batch
    delete_dns_records
    verify_deletion
    
    echo
    print_success "=== DNS 정리 완료 ==="
    print_info "이제 terraform destroy를 안전하게 실행할 수 있습니다."
    print_info "명령어: cd terraform && terraform destroy"
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi