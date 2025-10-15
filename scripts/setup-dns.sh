#!/bin/bash
# DNS 서버 설정 스크립트
# 각 노드에서 실행하여 DNS를 192.168.1.1로 설정합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DNS_SERVER="${DNS_SERVER:-192.168.1.1}"

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          DNS 서버 설정 스크립트                ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "DNS 서버: ${GREEN}${DNS_SERVER}${NC}"
echo ""

# 현재 DNS 확인
echo -e "${YELLOW}현재 DNS 설정:${NC}"
cat /etc/resolv.conf | grep "^nameserver"
echo ""

# systemd-resolved 사용 여부 확인
if systemctl is-active --quiet systemd-resolved; then
    echo -e "${BLUE}systemd-resolved 사용 중${NC}"

    # /etc/systemd/resolved.conf 설정
    echo -e "${YELLOW}systemd-resolved 설정 중...${NC}"

    RESOLVED_CONF="/etc/systemd/resolved.conf"

    # 백업
    if [ ! -f "${RESOLVED_CONF}.backup" ]; then
        sudo cp "${RESOLVED_CONF}" "${RESOLVED_CONF}.backup"
        echo -e "${GREEN}✓ 설정 파일 백업 완료${NC}"
    fi

    # DNS 설정
    sudo tee "${RESOLVED_CONF}" > /dev/null <<EOF
[Resolve]
DNS=${DNS_SERVER}
FallbackDNS=8.8.8.8 8.8.4.4
#Domains=
#LLMNR=no
#MulticastDNS=no
#DNSSEC=no
#DNSOverTLS=no
#Cache=yes
#DNSStubListener=yes
EOF

    echo -e "${GREEN}✓ systemd-resolved 설정 완료${NC}"

    # 서비스 재시작
    echo -e "${YELLOW}서비스 재시작 중...${NC}"
    sudo systemctl restart systemd-resolved

    echo -e "${GREEN}✓ systemd-resolved 재시작 완료${NC}"

else
    echo -e "${BLUE}systemd-resolved 미사용${NC}"

    # /etc/resolv.conf 직접 수정
    echo -e "${YELLOW}/etc/resolv.conf 설정 중...${NC}"

    # 백업
    if [ ! -f "/etc/resolv.conf.backup" ]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.backup
        echo -e "${GREEN}✓ resolv.conf 백업 완료${NC}"
    fi

    # DNS 설정
    sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver ${DNS_SERVER}
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

    echo -e "${GREEN}✓ resolv.conf 설정 완료${NC}"
fi

# 설정 확인
echo ""
echo -e "${YELLOW}변경된 DNS 설정:${NC}"
cat /etc/resolv.conf | grep "^nameserver"
echo ""

# DNS 테스트
echo -e "${YELLOW}DNS 테스트 중...${NC}"

# Google DNS 테스트
if nslookup google.com > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 인터넷 DNS 해석 성공 (google.com)${NC}"
else
    echo -e "${RED}✗ 인터넷 DNS 해석 실패${NC}"
fi

# MinIO Console 테스트
if nslookup console.minio.miribit.lab > /dev/null 2>&1; then
    MINIO_IP=$(nslookup console.minio.miribit.lab 2>/dev/null | grep "^Address:" | tail -1 | awk '{print $2}')
    echo -e "${GREEN}✓ MinIO Console DNS 해석 성공 (${MINIO_IP})${NC}"
else
    echo -e "${YELLOW}⚠ MinIO Console DNS 해석 실패 - /etc/hosts에 수동 추가 필요${NC}"
    echo ""
    echo "다음 명령으로 수동 추가:"
    echo "  sudo bash -c 'echo \"172.16.203.1 console.minio.miribit.lab s3.minio.miribit.lab\" >> /etc/hosts'"
fi

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           DNS 설정 완료!                       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}참고:${NC}"
echo "  - DNS 변경사항은 즉시 적용됩니다"
echo "  - 백업 파일이 생성되었습니다"
echo "  - 문제 발생 시 백업 파일로 복원 가능"
