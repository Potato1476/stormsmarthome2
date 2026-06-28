#!/usr/bin/env bash
# ============================================================================
# KỊCH BẢN ĐIỀU KHIỂN & DEMO DỰ ÁN FOG SMART HOME (GATEWAY LOCAL)
# ============================================================================
set -euo pipefail

# Di chuyển đến thư mục chứa script
cd "$(dirname "$0")"

ENV_FILE=".env.gateway"
COMPOSE_FILE="docker-compose.gateway.yml"

# Màu sắc hiển thị
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;60m' # No Color
BOLD='\033[1m'

get_cloud_ip() {
    local ip=""
    ip=$(cd infrastructure/terraform && terraform output -raw cloud_public_ip 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
        # Đọc từ .env.gateway nếu không gọi được terraform
        ip=$(grep "^CLOUD_PUBLIC_IP=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
    fi
    if [[ -z "$ip" ]]; then
        ip="52.74.153.60" # IP mặc định fallback
    fi
    echo "$ip"
}

get_optimizer_status() {
    if [[ -f "results/energy_optimizer.pid" ]]; then
        local pid
        pid=$(cat results/energy_optimizer.pid 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}ĐANG HOẠT ĐỘNG (PID: $pid)${NC}"
            return 0
        fi
    fi
    echo -e "${RED}ĐÃ TẮT${NC}"
    return 1
}

stop_optimizer_if_running() {
    if [[ -f "results/energy_optimizer.pid" ]]; then
        local pid
        pid=$(cat results/energy_optimizer.pid 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "\n${YELLOW}>>> Đang dừng Bộ tối ưu năng lượng tự động (PID: $pid)...${NC}"
            kill "$pid" 2>/dev/null || true
        fi
        rm -f results/energy_optimizer.pid
    fi
}

print_menu() {
    clear
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    echo -e "${BLUE}${BOLD}                 MENU ĐIỀU KHIỂN DỰ ÁN FOG SMART HOME                 ${NC}"
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    local ip
    ip=$(get_cloud_ip)
    echo -e "Trạng thái IP Cloud: ${GREEN}$ip${NC}"
    local opt_status
    opt_status=$(get_optimizer_status) || true
    echo -e "Bộ tối ưu năng lượng tự động: $opt_status"
    echo -e "----------------------------------------------------------------------"
    echo -e " ${BOLD}[1] CẤU HÌNH & KHỞI ĐỘNG GATEWAY${NC}"
    echo -e "     a. Đồng bộ IP Cloud (Tự động nhận diện từ Terraform hoặc nhập thủ công)"
    echo -e "     b. Bật 8 Gateway local (Chế độ Phân tán - Khuyên dùng)"
    echo -e "     c. Bật 1 Gateway local (Chế độ Single-node gánh 40 nhà)"
    echo -e "----------------------------------------------------------------------"
    echo -e " ${BOLD}[2] GIÁM SÁT & KIỂM TRA${NC}"
    echo -e "     d. Hiện liên kết Dashboard (Grafana, Prometheus, Storm UI)"
    echo -e "     e. Xem trạng thái các container đang chạy"
    echo -e "     f. Theo dõi logs cảnh báo (Slack/Alert)"
    echo -e "     g. Bật/Tắt Bộ tối ưu năng lượng tự động (Elastic Fog Nodes)"
    echo -e "----------------------------------------------------------------------"
    echo -e " ${BOLD}[3] TẮT HỆ THỐNG${NC}"
    echo -e "     x. Dừng toàn bộ Gateway local"
    echo -e "----------------------------------------------------------------------"
    echo -e " [0] Thoát"
    echo -e "======================================================================"
    echo -n "Nhập lựa chọn của bạn (ví dụ: a, b, d, x): "
}

sync_cloud_ip() {
    echo -e "\n${YELLOW}>>> Đồng bộ IP Cloud...${NC}"
    echo -n "Nhập IP Cloud (để trống để tự động lấy từ Terraform): "
    read -r manual_ip || true
    if [[ -n "$manual_ip" ]]; then
        ./infrastructure/scripts/set-cloud-ip.sh "$manual_ip"
    else
        ./infrastructure/scripts/set-cloud-ip.sh
    fi
    echo -e "${GREEN}Đồng bộ IP thành công!${NC}"
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

start_gateways_multi() {
    echo -e "\n${YELLOW}>>> Đang dừng và dọn dẹp các container của chế độ Single-node nếu có...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop gw-single 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" rm -f gw-single 2>/dev/null || true

    echo -e "\n${YELLOW}>>> Đang bật 8 Gateway local (Chế độ Phân tán)...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile multi up -d
    echo -e "${GREEN}Đã kích hoạt 8 Gateway và các dịch vụ giám sát (Grafana, Prometheus).${NC}"
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

start_gateways_single() {
    # Tắt bộ tối ưu nếu đang chạy (vì chế độ single-gateway không cần tối ưu năng lượng)
    stop_optimizer_if_running

    echo -e "\n${YELLOW}>>> Đang dừng và dọn dẹp các container của chế độ Phân tán nếu có...${NC}"
    for i in {1..8}; do
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop "gw-0$i" 2>/dev/null || true
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" rm -f "gw-0$i" 2>/dev/null || true
    done

    echo -e "\n${YELLOW}>>> Đang bật 1 Gateway local (Chế độ Single-node)...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile single up -d
    echo -e "${GREEN}Đã kích hoạt 1 Gateway (phục vụ 40 nhà) và các dịch vụ giám sát.${NC}"
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

show_urls() {
    echo -e "\n${YELLOW}>>> Các liên kết giám sát dự án:${NC}"
    local ip
    ip=$(get_cloud_ip)
    echo -e "  - ${BOLD}Web Dashboard (Grafana):${NC}  http://localhost:3000 (tài khoản: ${BOLD}admin / admin${NC})"
    echo -e "  - ${BOLD}Prometheus Local Exporter:${NC} http://localhost:9090"
    echo -e "  - ${BOLD}Storm UI (Nimbus Cloud):${NC}  http://$ip:8080"
    echo -e "----------------------------------------------------------------------"
    echo -e "Mẹo: Mở Grafana -> chọn dashboard ${BOLD}Fog vs Monolithic${NC} để xem thời gian thực."
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

show_status() {
    echo -e "\n${YELLOW}>>> Trạng thái các container đang chạy cục bộ (Gateway):${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

monitor_logs() {
    echo -e "\n${YELLOW}>>> Đang theo dõi log cảnh báo Slack (Nhấn Ctrl+C để thoát)...${NC}"
    docker logs -f gw-single 2>&1 | grep -iE 'ALERT|anomaly|slack' || \
    docker logs -f gw-01 2>&1 | grep -iE 'ALERT|anomaly|slack' || \
    echo -e "${RED}Không kết nối được logs (Hãy đảm bảo gateway đã chạy).${NC}"
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

toggle_optimizer() {
    if [[ -f "results/energy_optimizer.pid" ]]; then
        local pid
        pid=$(cat results/energy_optimizer.pid 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "\n${YELLOW}>>> Đang dừng Bộ tối ưu năng lượng tự động...${NC}"
            kill "$pid" 2>/dev/null || true
            rm -f results/energy_optimizer.pid
            echo -e "${GREEN}Đã dừng thành công!${NC}"
            read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
            return
        fi
    fi

    echo -e "\n${YELLOW}>>> Đang khởi động Bộ tối ưu năng lượng tự động...${NC}"
    nohup node tools/energy_optimizer.js > results/energy_optimizer_console.log 2>&1 &
    echo "$!" > results/energy_optimizer.pid
    echo -e "${GREEN}Đã bật Bộ tối ưu năng lượng (PID: $!). Theo dõi log tại results/energy_optimization.log${NC}"
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

stop_gateways_only() {
    echo -e "\n${YELLOW}>>> Đang dừng các container gateway ở local...${NC}"
    # Dừng bộ tối ưu nếu đang chạy
    stop_optimizer_if_running
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile multi --profile single down
    echo -e "${GREEN}Đã dừng các gateway local thành công.${NC}"
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

# Vòng lặp chính
while true; do
    print_menu
    read -r choice
    case $choice in
        a|A) sync_cloud_ip ;;
        b|B) start_gateways_multi ;;
        c|C) start_gateways_single ;;
        d|D) show_urls ;;
        e|E) show_status ;;
        f|F) monitor_logs ;;
        g|G) toggle_optimizer ;;
        x|X) stop_gateways_only ;;
        0) echo -e "\n${GREEN}Tạm biệt! Chúc buổi demo của bạn thành công tốt đẹp.${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Lựa chọn không hợp lệ!${NC}"; sleep 1 ;;
    esac
done
