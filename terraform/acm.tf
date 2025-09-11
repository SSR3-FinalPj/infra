# ============================================
# ACM (Amazon Certificate Manager) Configuration
# ============================================
# AWS Certificate Manager를 사용한 SSL/TLS 인증서 관리
# Route 53 호스팅 영역과 연동하여 DNS 검증 자동화
# ============================================

# Route 53 호스팅 영역 생성
# 무료 도메인을 AWS Route 53으로 DNS 관리 이관
resource "aws_route53_zone" "main" {
  name = var.domain_name
  
  tags = {
    Name        = "${var.domain_name}-hosted-zone"
    Description = "Route 53 hosted zone for ${var.domain_name}"
  }
}

# ACM 인증서 요청
# 도메인과 와일드카드 서브도메인을 포함한 인증서
resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  subject_alternative_names = [
    "*.${var.domain_name}"  # 와일드카드로 모든 서브도메인 커버
  ]
  
  validation_method = "DNS"  # DNS 검증 방식 사용
  
  # 인증서 교체 시 기존 인증서 삭제 전 새 인증서 생성
  lifecycle {
    create_before_destroy = true
  }
  
  tags = {
    Name        = "${var.domain_name}-certificate"
    Description = "ACM certificate for ${var.domain_name} and wildcard subdomains"
  }
}

# DNS 검증 레코드 생성
# ACM이 제공하는 검증 정보를 Route 53에 자동 등록
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# 인증서 검증 완료 대기
# DNS 검증이 완료되고 인증서가 발급될 때까지 대기
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  
  # 인증서 검증 타임아웃 (기본 5분, 최대 10분으로 설정)
  timeouts {
    create = "10m"
  }
}

# ============================================
# 참고사항
# ============================================
# ALB DNS 레코드는 여기서 생성하지 않습니다.
# 이유: Terraform 실행 시점에 ALB가 아직 존재하지 않기 때문
# 
# ALB DNS 레코드 생성 방법:
# 1. Ansible 배포 후 ALB 생성 확인
# 2. 수동으로 Route 53에 A 레코드 (ALIAS) 생성:
#    - front.meaire.kro.kr → k8s-devsyste-external-xxxx.us-east-2.elb.amazonaws.com
#    - api.meaire.kro.kr → k8s-devsyste-backendi-xxxx.us-east-2.elb.amazonaws.com
# 3. 또는 별도 Terraform 스크립트로 Phase 2 실행
# ============================================