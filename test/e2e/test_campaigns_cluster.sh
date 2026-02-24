#!/usr/bin/env bash
# Cluster E2E test for campaign system.
# Verifies: gateway connectivity, campaign trigger, status polling,
# Setec storage, and KPI assertions against a live fuzzy-dev cluster.
#
# Prerequisites:
#   - kubectl configured for fuzzy-dev cluster
#   - Gateway accessible (tailnet or port-forward)
#
# Usage:
#   ./test_campaigns_cluster.sh [GATEWAY_URL]
#
# Environment:
#   GATEWAY_URL      rj-gateway base URL (default: http://127.0.0.1:8080)
#   RUNNER_URL       campaign-runner API URL (default: http://127.0.0.1:8081)
#   CAMPAIGN_ID      campaign to trigger (default: oc-gateway-smoketest)
#   POLL_TIMEOUT     max seconds to poll for result (default: 120)
#   SKIP_K8S_CHECK   set to 1 to skip kubectl health checks

set -euo pipefail

# Colors for output.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

GATEWAY_URL="${GATEWAY_URL:-${1:-http://127.0.0.1:8080}}"
RUNNER_URL="${RUNNER_URL:-http://127.0.0.1:8081}"
CAMPAIGN_ID="${CAMPAIGN_ID:-oc-gateway-smoketest}"
POLL_TIMEOUT="${POLL_TIMEOUT:-120}"
SKIP_K8S_CHECK="${SKIP_K8S_CHECK:-0}"

pass=0
fail=0
skip=0

log_pass() { echo -e "${GREEN}PASS${NC}: $1"; pass=$((pass + 1)); }
log_fail() { echo -e "${RED}FAIL${NC}: $1"; fail=$((fail + 1)); }
log_skip() { echo -e "${YELLOW}SKIP${NC}: $1"; skip=$((skip + 1)); }
log_info() { echo -e "INFO: $1"; }

# --- Phase 1: Cluster Health ---

log_info "=== Phase 1: Cluster Health ==="

if [ "$SKIP_K8S_CHECK" = "1" ]; then
    log_skip "kubectl checks (SKIP_K8S_CHECK=1)"
else
    # Check gateway pod is running.
    if kubectl get pods -n fuzzy-dev -l app=rj-gateway --field-selector=status.phase=Running -o name 2>/dev/null | grep -q pod; then
        log_pass "rj-gateway pod is running"
    else
        log_fail "rj-gateway pod not found or not running"
    fi

    # Check openclaw pod is running.
    if kubectl get pods -n fuzzy-dev -l app=openclaw-agent --field-selector=status.phase=Running -o name 2>/dev/null | grep -q pod; then
        log_pass "openclaw pod is running"
    else
        log_fail "openclaw pod not found or not running"
    fi

    # Check campaign-definitions ConfigMap exists.
    if kubectl get configmap campaign-definitions -n fuzzy-dev -o name 2>/dev/null | grep -q configmap; then
        log_pass "campaign-definitions ConfigMap exists"
    else
        log_fail "campaign-definitions ConfigMap not found"
    fi
fi

# --- Phase 2: Gateway Connectivity ---

log_info "=== Phase 2: Gateway Connectivity ==="

# Gateway health.
health_resp=$(curl -s -o /dev/null -w "%{http_code}" "${GATEWAY_URL}/health" 2>/dev/null || echo "000")
if [ "$health_resp" = "200" ]; then
    log_pass "gateway /health returns 200"
else
    log_fail "gateway /health returned $health_resp (expected 200)"
fi

# Gateway health body.
health_body=$(curl -s "${GATEWAY_URL}/health" 2>/dev/null || echo "{}")
if echo "$health_body" | grep -q '"status":"ok"'; then
    log_pass "gateway health status is 'ok'"
else
    log_fail "gateway health body unexpected: $health_body"
fi

# MCP tools/list.
tools_resp=$(curl -s -X POST "${GATEWAY_URL}/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null || echo "{}")
tool_count=$(echo "$tools_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('result',{}).get('tools',[])))" 2>/dev/null || echo "0")
if [ "$tool_count" -gt 0 ]; then
    log_pass "MCP tools/list returns $tool_count tools"
else
    log_fail "MCP tools/list returned 0 tools"
fi

# --- Phase 3: Campaign Runner ---

log_info "=== Phase 3: Campaign Runner ==="

# Runner health.
runner_health=$(curl -s -o /dev/null -w "%{http_code}" "${RUNNER_URL}/health" 2>/dev/null || echo "000")
if [ "$runner_health" = "200" ]; then
    log_pass "campaign-runner /health returns 200"
else
    log_fail "campaign-runner /health returned $runner_health (expected 200)"
fi

# Campaigns list.
campaigns_resp=$(curl -s "${RUNNER_URL}/campaigns" 2>/dev/null || echo "{}")
campaign_count=$(echo "$campaigns_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('count',0))" 2>/dev/null || echo "0")
if [ "$campaign_count" -gt 0 ]; then
    log_pass "campaign-runner lists $campaign_count campaigns"
else
    log_fail "campaign-runner lists 0 campaigns"
fi

# --- Phase 4: Trigger Campaign ---

log_info "=== Phase 4: Trigger Campaign ($CAMPAIGN_ID) ==="

trigger_resp=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${RUNNER_URL}/trigger?campaign=${CAMPAIGN_ID}" 2>/dev/null || echo "000")
if [ "$trigger_resp" = "202" ]; then
    log_pass "campaign $CAMPAIGN_ID triggered (202 Accepted)"
else
    log_fail "trigger returned $trigger_resp (expected 202)"
fi

# --- Phase 5: Poll for Result ---

log_info "=== Phase 5: Poll Status (timeout=${POLL_TIMEOUT}s) ==="

elapsed=0
poll_interval=5
campaign_status="no_runs"

while [ "$elapsed" -lt "$POLL_TIMEOUT" ]; do
    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))

    status_resp=$(curl -s "${RUNNER_URL}/status?campaign=${CAMPAIGN_ID}" 2>/dev/null || echo "{}")
    campaign_status=$(echo "$status_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','no_runs'))" 2>/dev/null || echo "unknown")

    if [ "$campaign_status" = "success" ] || [ "$campaign_status" = "failure" ] || [ "$campaign_status" = "error" ] || [ "$campaign_status" = "timeout" ]; then
        break
    fi

    log_info "  polling... (${elapsed}s, status=$campaign_status)"
done

if [ "$campaign_status" = "success" ]; then
    log_pass "campaign completed with status 'success'"
elif [ "$campaign_status" = "no_runs" ]; then
    log_fail "campaign did not produce a result within ${POLL_TIMEOUT}s"
else
    log_fail "campaign completed with status '$campaign_status'"
fi

# --- Phase 6: Verify Setec Storage ---

log_info "=== Phase 6: Verify Setec Storage ==="

setec_resp=$(curl -s -X POST "${GATEWAY_URL}/mcp" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"juggler_setec_get\",\"arguments\":{\"key\":\"remotejuggler/campaigns/${CAMPAIGN_ID}/latest\"}}}" 2>/dev/null || echo "{}")

setec_has_result=$(echo "$setec_resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
content=d.get('result',{}).get('content',[])
if content:
    inner=json.loads(content[0].get('text','{}'))
    print('yes' if inner.get('campaign_id') else 'no')
else:
    print('no')
" 2>/dev/null || echo "no")

if [ "$setec_has_result" = "yes" ]; then
    log_pass "campaign result stored in Setec"

    # Extract tool_calls KPI.
    tool_calls=$(echo "$setec_resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
content=d.get('result',{}).get('content',[])
if content:
    inner=json.loads(content[0].get('text','{}'))
    print(inner.get('tool_calls',0))
else:
    print(0)
" 2>/dev/null || echo "0")

    if [ "$tool_calls" -gt 0 ]; then
        log_pass "campaign reported $tool_calls tool calls"
    else
        log_fail "campaign reported 0 tool calls"
    fi
else
    log_fail "campaign result not found in Setec"
fi

# --- Phase 7: Verify Metering ---

log_info "=== Phase 7: Verify Metering (Aperture Usage) ==="

meter_resp=$(curl -s -X POST "${GATEWAY_URL}/mcp" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"juggler_aperture_usage\",\"arguments\":{}}}" 2>/dev/null || echo "{}")

meter_has_data=$(echo "$meter_resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
content=d.get('result',{}).get('content',[])
if content:
    inner=json.loads(content[0].get('text','{}'))
    calls=inner.get('mcp_tool_calls',0)
    tokens=inner.get('total_tokens',0)
    print(f'yes calls={calls} tokens={tokens}')
else:
    print('no')
" 2>/dev/null || echo "no")

if echo "$meter_has_data" | grep -q "^yes"; then
    log_pass "aperture_usage returns metering data ($meter_has_data)"
else
    log_skip "aperture_usage metering data not available (may need active requests)"
fi

# --- Summary ---

echo ""
echo "================================="
echo -e "  ${GREEN}PASS: $pass${NC}  ${RED}FAIL: $fail${NC}  ${YELLOW}SKIP: $skip${NC}"
echo "================================="

if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
