#!/usr/bin/env bash
# ============================================================================
# AUTOMATED TEST: Fog Energy Optimizer (Tối ưu năng lượng tự động)
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}=== STARTING AUTOMATED TEST FOR ENERGY OPTIMIZER ===${NC}"

# 1. Ensure stack is running in multi profile
echo -e "\n[1/5] Ensuring gateways are running in 'multi' profile..."
docker compose -f docker-compose.gateway.yml --env-file .env.gateway --profile multi up -d >/dev/null

# Unpause all initially to ensure a clean starting point
for i in {1..8}; do
  docker compose -f docker-compose.gateway.yml --env-file .env.gateway unpause "gw-0$i" 2>/dev/null || true
done
sleep 2

# 2. Start energy optimizer in background
echo -e "\n[2/5] Starting energy_optimizer.js daemon in background..."
node tools/energy_optimizer.js > results/test_optimizer_daemon.log 2>&1 &
OPT_PID=$!

cleanup() {
  echo -e "\n${YELLOW}Cleaning up background processes...${NC}"
  kill "$OPT_PID" 2>/dev/null || true
  # Ensure all gateways are unpaused when exiting the test
  for i in {1..8}; do
    docker compose -f docker-compose.gateway.yml --env-file .env.gateway unpause "gw-0$i" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# 3. Wait for idle timeout (gateways should pause since no traffic is published)
echo -e "\n[3/5] Waiting 18 seconds for idle detection (threshold = 15s)..."
sleep 18

# Verify all gateways are paused
all_paused=true
for i in {1..8}; do
  gw="gw-0$i"
  status=$(docker inspect -f '{{.State.Status}}' "$gw" 2>/dev/null || echo "not_found")
  if [[ "$status" == "paused" ]]; then
    echo -e "  ✅ $gw is ${GREEN}paused${NC} (Correct: idle)"
  else
    echo -e "  ❌ $gw is in state: ${RED}$status${NC} (Expected: paused)"
    all_paused=false
  fi
done

if [ "$all_paused" = false ]; then
  echo -e "\n${RED}${BOLD}TEST FAILED: Idle gateways were not automatically paused.${NC}"
  exit 1
fi

# 4. Simulate traffic for house-0 (gw-01)
echo -e "\n[4/5] Simulating sensor readings for house-0 (belongs to gw-01)..."
# MQTT payload fields: idx,timestamp,value,property,plugId,householdId,houseId (houseId = 0 at index 6)
docker exec local-mqtt mosquitto_pub -t iot-data -m "123,1715592259,350.5,1,2,3,0"
sleep 4 # wait for check interval

# 5. Verify gw-01 is unpaused (running) and others remain paused
echo -e "\n[5/5] Verifying gateway activation states..."
gw01_status=$(docker inspect -f '{{.State.Status}}' gw-01 2>/dev/null)
if [[ "$gw01_status" == "running" ]]; then
  echo -e "  ✅ gw-01 successfully ${GREEN}activated (running)${NC} on incoming traffic."
else
  echo -e "  ❌ gw-01 failed to activate! Current state: ${RED}$gw01_status${NC}"
  exit 1
fi

others_stayed_paused=true
for i in {2..8}; do
  gw="gw-0$i"
  status=$(docker inspect -f '{{.State.Status}}' "$gw" 2>/dev/null)
  if [[ "$status" != "paused" ]]; then
    echo -e "  ❌ $gw incorrectly woke up! State: ${RED}$status${NC}"
    others_stayed_paused=false
  fi
done

if [ "$others_stayed_paused" = true ]; then
  echo -e "  ✅ All other gateways remained in ${GREEN}paused${NC} power-saving state."
else
  echo -e "\n${RED}${BOLD}TEST FAILED: Unrelated gateways woke up without traffic.${NC}"
  exit 1
fi

echo -e "\n${GREEN}${BOLD}====================================================${NC}"
# Translate: ALL TESTS PASSED: Energy optimizer works correctly!
echo -e "${GREEN}${BOLD}  TẤT CẢ KIỂM THỬ THÀNH CÔNG: Bộ tối ưu năng lượng hoạt động hoàn hảo! ${NC}"
echo -e "${GREEN}${BOLD}====================================================${NC}"
exit 0
