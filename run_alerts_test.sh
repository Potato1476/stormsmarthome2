#!/usr/bin/env bash
# ============================================================================
# KỊCH BẢN CHẠY THỬ CẢNH BÁO SLACK & PHÁT HIỆN BẤT THƯỜNG TẠI EDGE (GATEWAY)
# ============================================================================
set -euo pipefail

# Di chuyển đến thư mục của script
cd "$(dirname "$0")"

ENV_FILE=".env.gateway"
COMPOSE_FILE="docker-compose.gateway.yml"
PUBLISHER_SCRIPT="./tools/publish_csv.sh"
IOT_PUBLISHER_DIR="/Users/nguyenbao/iot-data-publisher"

# Màu sắc hiển thị
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;60m' # No Color
BOLD='\033[1m'

# Kiểm tra file cấu hình
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${YELLOW}[ALERT] Không thấy file $ENV_FILE. Đang copy từ ví dụ...${NC}"
    cp .env.gateway.example "$ENV_FILE"
    echo -e "${YELLOW}[ALERT] Đã tạo file $ENV_FILE. Hãy cập nhật SLACK_WEBHOOK_URL vào file này trước khi tiếp tục!${NC}"
fi

# Đọc Slack Webhook URL từ file .env.gateway
SLACK_WEBHOOK_URL=$(grep "^SLACK_WEBHOOK_URL=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

print_header() {
    clear
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    echo -e "${BLUE}${BOLD}      KỊCH BẢN CHẠY THỬ HỆ THỐNG CẢNH BÁO ĐA KÊNH & ANOMALY DETECTOR      ${NC}"
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    echo -e "Trạng thái webhook Slack hiện tại:"
    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        echo -e "  Webhook: ${RED}CHƯA ĐƯỢC CẤU HÌNH (Sẽ tắt cảnh báo Slack)${NC}"
    else
        # Ẩn bớt ký tự nhạy cảm
        masked_webhook="${SLACK_WEBHOOK_URL:0:40}..."
        echo -e "  Webhook: ${GREEN}$masked_webhook${NC}"
    fi
    echo -e "----------------------------------------------------------------------"
}

check_webhook_direct() {
    echo -e "\n${YELLOW}[1/6] Kiểm tra trực tiếp Slack Webhook (Không cần chạy Docker/Storm)...${NC}"
    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        echo -e "${RED}Lỗi: Vui lòng điền SLACK_WEBHOOK_URL vào file $ENV_FILE trước!${NC}"
        read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
        return
    fi

    echo -e "${BLUE}Đang biên dịch module fog-gateway cục bộ bằng Maven...${NC}"
    if mvn clean package -pl fog-gateway -am -DskipTests; then
        echo -e "${GREEN}Biên dịch thành công!${NC}"
        echo -e "${BLUE}Đang gửi tin nhắn cảnh báo CRITICAL mẫu tới Slack...${NC}"
        java -cp fog-gateway/target/fog-gateway-1.0-jar-with-dependencies.jar \
             com.storm.iotdata.fog.alert.SlackNotifier "$SLACK_WEBHOOK_URL"
        echo -e "${GREEN}Đã gửi lệnh test. Hãy kiểm tra kênh Slack của bạn!${NC}"
    else
        echo -e "${RED}Lỗi: Biên dịch Maven thất bại.${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

start_gateway_containers() {
    echo -e "\n${YELLOW}[2/6] Đang dựng docker image & khởi chạy Gateway Single-node...${NC}"
    
    echo -e "${BLUE}1. Build image docker fog-gateway:latest...${NC}"
    docker compose -f "$COMPOSE_FILE" build gw-single
    
    echo -e "${BLUE}2. Khởi chạy container gw-single và broker local-mqtt...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile single up -d gw-single mqtt-broker
    
    echo -e "${GREEN}Đã khởi chạy thành công các container!${NC}"
    docker ps --filter "name=gw-single" --filter "name=local-mqtt"
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

send_synthetic_data() {
    echo -e "\n${YELLOW}[3/6] Bơm dữ liệu giả lập (0..3000W, sinh ngẫu nhiên)...${NC}"
    echo -e "Ngưỡng cảnh báo trần cứng là: 2500 W."
    echo -e "Dữ liệu giả lập sẽ vượt ngưỡng 2500 W ngẫu nhiên và kích hoạt cảnh báo."
    echo ""
    
    # Chạy publish_csv.sh ở chế độ giả lập
    $PUBLISHER_SCRIPT --synthetic 1000 100
    
    echo -e "\n${GREEN}Đã gửi dữ liệu giả lập xong!${NC}"
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

send_real_csv_data() {
    echo -e "\n${YELLOW}[4/6] Bơm dữ liệu thực tế từ file CSV...${NC}"
    
    # Tìm file CSV thực tế từ thư mục iot-data-publisher
    local csv_dir="$IOT_PUBLISHER_DIR/data-file"
    if [[ ! -d "$csv_dir" ]]; then
        echo -e "${RED}Không tìm thấy thư mục dữ liệu thực tế tại: $csv_dir${NC}"
        echo -e "Hãy kiểm tra xem thư mục $IOT_PUBLISHER_DIR có tồn tại không."
        read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
        return
    fi
    
    echo -e "${BLUE}Danh sách file CSV có sẵn trong $csv_dir:${NC}"
    # Hiện vài file tiêu biểu
    ls -1 "$csv_dir" | head -n 10
    echo -e "..."
    
    echo -e -n "\nNhập tên file CSV muốn chạy (ví dụ: house-0.csv): "
    read -r selected_file
    
    local full_path="$csv_dir/$selected_file"
    if [[ ! -f "$full_path" ]]; then
        echo -e "${RED}Không tìm thấy file: $full_path${NC}"
        read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
        return
    fi
    
    echo -e -n "Nhập tốc độ gửi (số dòng/giây, mặc định 100): "
    read -r send_rate
    send_rate="${send_rate:-100}"
    
    echo -e "${BLUE}Bắt đầu gửi dữ liệu từ file $selected_file với tốc độ $send_rate dòng/giây...${NC}"
    $PUBLISHER_SCRIPT "$full_path" "$send_rate"
    
    echo -e "\n${GREEN}Đã hoàn thành gửi file CSV thực tế!${NC}"
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

monitor_logs() {
    echo -e "\n${YELLOW}[5/6] Đang theo dõi log của gw-single (Xem log phát hiện bất thường và gửi Slack)...${NC}"
    echo -e "${BLUE}Bấm Ctrl+C để ngừng theo dõi và quay lại menu.${NC}\n"
    
    # Kiểm tra xem container có đang chạy không
    if ! docker ps -q --filter "name=gw-single" | grep -q . ; then
        echo -e "${RED}Cảnh báo: Container gw-single hiện chưa chạy! Hãy chạy bước [2] trước.${NC}"
        echo ""
    fi
    
    # In log và lọc các từ khóa liên quan đến ALERT và Slack
    docker logs -f gw-single 2>&1 | grep -iE 'ALERT|anomaly|slack|publish' || true
    
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

cleanup_containers() {
    echo -e "\n${YELLOW}[6/6] Đang dừng và dọn dẹp các container gateway...${NC}"
    docker compose -f "$COMPOSE_FILE" --profile single down
    echo -e "${GREEN}Đã dọn dẹp xong!${NC}"
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để quay lại menu..."
}

# Vòng lặp Menu chính
while true; do
    print_header
    echo -e "Chọn thao tác để thực hiện:"
    echo -e "  1. ${BOLD}Test trực tiếp Slack Webhook${NC} (Bắn 1 tin nhắn test nhanh)"
    echo -e "  2. ${BOLD}Khởi động Gateway single-node & Broker MQTT${NC} (Docker compose)"
    echo -e "  3. ${BOLD}Bơm dữ liệu giả lập${NC} (--synthetic, vượt trần 2500W để phát cảnh báo)"
    echo -e "  4. ${BOLD}Bơm dữ liệu thực tế từ file CSV${NC} (Lấy từ folder iot-data-publisher)"
    echo -e "  5. ${BOLD}Theo dõi Logs phát hiện bất thường & Slack${NC}"
    echo -e "  6. ${BOLD}Dừng và dọn dẹp các container${NC}"
    echo -e "  0. Thoát"
    echo -e "----------------------------------------------------------------------"
    echo -n "Lựa chọn của bạn (0-6): "
    read -r opt
    
    case $opt in
        1) check_webhook_direct ;;
        2) start_gateway_containers ;;
        3) send_synthetic_data ;;
        4) send_real_csv_data ;;
        5) monitor_logs ;;
        6) cleanup_containers ;;
        0) echo -e "\n${GREEN}Cảm ơn bạn! Tạm biệt.${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Lựa chọn không hợp lệ! Vui lòng chọn lại (0-6).${NC}"; sleep 1 ;;
    esac
done
