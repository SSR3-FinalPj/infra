# 🚨 EKS AlertManager 실무 설정 가이드

## 📋 개요

이 AlertManager 설정은 우리 EKS 클러스터의 **17개 서비스 스택**을 위한 실무 중심의 알림 시스템입니다.

---

## 🎯 알림 우선순위 체계

### **P0: 즉시 대응 (5분 이내)**
- **노드 다운**: 클러스터 가용성 직접 영향
- **메모리/디스크 크리티컬**: OOM Kill, 스케줄링 실패 위험
- **Kubernetes API 다운**: 전체 클러스터 관리 불가

### **P1: 긴급 대응 (15분 이내)**
- **핵심 서비스 다운**: Kafka, PostgreSQL, Redis, Elasticsearch
- **Pod 크래시 루프**: 애플리케이션 불안정
- **VPC CNI 에러**: 네트워킹 인프라 문제

### **P2: 중요 대응 (30분 이내)**
- **리소스 임계값**: CPU/메모리 > 80%
- **디스크 사용률 높음**: 용량 부족 예상
- **Pod CPU 쓰로틀링**: 성능 저하

### **P3: 정보성 (1시간 이내)**
- **성능 지표**: 로드 평균 높음, 네트워크 에러
- **용량 계획**: Pod 밀도 높음

---

## 🔧 Slack 연동 설정

### **1. Slack 웹훅 URL 생성**

```bash
# Slack 앱 생성 및 웹훅 URL 획득 후
# values.yaml에서 다음 부분 수정:
# api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
```

### **2. 채널별 알림 분류**

| 채널 | 알림 종류 | 대상자 |
|-----|----------|--------|
| **#ops-critical** | P0 인프라 장애 | DevOps 팀, 온콜 엔지니어 |
| **#app-alerts** | P1 서비스 장애 | 개발팀, 서비스 담당자 |
| **#monitoring** | P2/P3 경고/정보 | 모니터링 팀, 관심자 |

---

## ⚙️ 알림 규칙 상세

### **인프라 크리티컬 알림**

```yaml
# 노드 다운 (1분 후 즉시 알림)
NodeDown: up{job="node-exporter"} == 0 for 1m

# 메모리 크리티컬 (95% 초과 2분)
NodeMemoryCritical: memory_usage > 95% for 2m

# 디스크 크리티컬 (90% 초과 5분)
NodeDiskSpaceCritical: disk_usage > 90% for 5m
```

### **애플리케이션 크리티컬 알림**

```yaml
# Pod 크래시 루프 (1시간에 2회 이상 재시작)
PodCrashLooping: restarts > 2/hour for 5m

# 서비스별 다운 감지
KafkaDown / PostgreSQLDown / RedisDown / ElasticsearchDown
```

### **리소스 경고 알림**

```yaml
# CPU 사용률 높음 (80% 초과 10분)
NodeCPUHigh: cpu_usage > 80% for 10m

# 메모리 사용률 높음 (80% 초과 10분)  
NodeMemoryHigh: memory_usage > 80% for 10m
```

---

## 🛡️ 알림 억제 규칙

중복 알림을 방지하는 지능형 억제:

1. **노드 다운 시**: 해당 노드의 모든 리소스 경고 억제
2. **API 서버 다운 시**: 클러스터의 모든 경고 억제
3. **애플리케이션 다운 시**: 해당 서비스의 성능 경고 억제

---

## 🚀 배포 및 테스트

### **1. 설정 배포**

```bash
cd ansible
ansible-playbook playbook.yml --tags "prometheus" \
  --extra-vars "@terraform_outputs.json" \
  --vault-password-file .vault_pass
```

### **2. AlertManager 접근**

```bash
# 포트 포워딩으로 접근
kubectl port-forward -n dev-system svc/monitoring-kube-prometheus-alertmanager 9093:80

# 브라우저에서 http://localhost:9093 접근
```

### **3. 테스트 알림 발송**

```bash
# CPU 부하 생성으로 테스트
kubectl run cpu-stress --image=progrium/stress -- --cpu 2

# 메모리 부하 생성으로 테스트  
kubectl run memory-stress --image=progrium/stress -- --vm 1 --vm-bytes 1G
```

---

## 📊 모니터링 대시보드와 연계

### **Grafana 알림 패널 추가**

기존 EKS 노드 모니터링 대시보드에 **알림 상태 패널** 추가 권장:

1. **활성 알림 수**: 현재 발생 중인 알림 개수
2. **알림 히스토리**: 최근 24시간 알림 발생 패턴  
3. **알림 해결률**: 알림 발생 대비 해결 비율

### **핵심 SLI/SLO 지표**

| 지표 | 목표 | 측정 방법 |
|-----|------|----------|
| **노드 가용성** | 99.9% | NodeDown 알림 발생률 |
| **서비스 가용성** | 99.5% | 애플리케이션 Down 알림 |
| **알림 응답 시간** | P0: 5분, P1: 15분 | 수동 트래킹 |

---

## 🔒 보안 및 시크릿 관리

### **민감 정보 암호화**

```bash
# Ansible Vault로 Slack 웹훅 URL 암호화
ansible-vault encrypt_string 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK' \
  --name 'slack_webhook_url' \
  --vault-password-file .vault_pass
```

### **접근 권한 설정**

- **AlertManager UI**: ALB Internal Ingress로 내부 접근만
- **Slack 채널**: 팀별 권한 분리
- **이메일**: 업무용 메일만 사용

---

## 📈 운영 최적화 팁

### **1. 알림 피로도 방지**

- **점진적 임계값 조정**: 초기에는 높게 설정 후 점진적 하향
- **시간대별 조정**: 업무시간 외에는 Critical만 알림
- **정기 리뷰**: 주간 알림 발생률 및 해결률 분석

### **2. 알림 품질 개선**

- **False Positive 최소화**: 실제 문제가 아닌 알림 제거
- **Context 정보 충실**: 알림에 대응 방법 포함
- **자동 해결 연계**: 가능한 경우 자동 복구 스크립트 연결

### **3. 확장성 고려**

- **서비스 추가 시**: 새 애플리케이션별 알림 규칙 추가
- **팀 확장 시**: 책임자별 알림 라우팅 세분화
- **멀티 클러스터**: 클러스터별 라벨링으로 구분

이 설정을 통해 **안정적이고 실무적인 알림 시스템**을 운영할 수 있습니다.