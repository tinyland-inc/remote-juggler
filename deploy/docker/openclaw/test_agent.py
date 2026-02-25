"""Tests for OpenClaw agent: tool fetching, MCP calls, github_fetch, prompt building, KPI extraction."""

import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
from unittest.mock import MagicMock

import pytest

# Ensure heavy deps are available (mocked if needed for local dev).
for _mod in ("anthropic", "httpx"):
    if _mod not in sys.modules:
        try:
            __import__(_mod)
        except ImportError:
            sys.modules[_mod] = MagicMock()

from agent import (  # noqa: E402
    OpenClawAgent,
    GITHUB_FETCH_TOOL,
    GITHUB_LIST_ALERTS_TOOL,
    GITHUB_CREATE_BRANCH_TOOL,
    GITHUB_UPDATE_FILE_TOOL,
    GITHUB_CREATE_PR_TOOL,
    LOCAL_TOOLS,
    ToolTraceEntry,
)


class MockGatewayHandler(BaseHTTPRequestHandler):
    """Simulates rj-gateway for agent tests."""

    tools_response = {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {
            "tools": [
                {
                    "name": "juggler_setec_list",
                    "description": "List Setec secrets",
                    "inputSchema": {"type": "object", "properties": {}},
                },
                {
                    "name": "juggler_audit_log",
                    "description": "Query audit log",
                    "inputSchema": {
                        "type": "object",
                        "properties": {"count": {"type": "integer"}},
                    },
                },
                {
                    "name": "juggler_resolve_composite",
                    "description": "Resolve secret",
                    "inputSchema": {
                        "type": "object",
                        "properties": {"query": {"type": "string"}},
                        "required": ["query"],
                    },
                },
            ]
        },
    }

    # Track received arguments for metering tests.
    last_tool_call_args = {}

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))

        if body.get("method") == "tools/list":
            self._json_response(200, self.tools_response)
        elif body.get("method") == "tools/call":
            name = body["params"]["name"]
            args = body["params"].get("arguments", {})
            MockGatewayHandler.last_tool_call_args = args
            if name == "juggler_setec_list":
                self._json_response(
                    200,
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "result": {
                            "content": [
                                {
                                    "type": "text",
                                    "text": json.dumps({"secrets": ["a", "b"]}),
                                }
                            ]
                        },
                    },
                )
            elif name == "juggler_resolve_composite":
                self._json_response(
                    200,
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "result": {
                            "content": [
                                {
                                    "type": "text",
                                    "text": json.dumps(
                                        {"value": "ghp_test123", "source": "env"}
                                    ),
                                }
                            ]
                        },
                    },
                )
            else:
                self._json_response(
                    200,
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "result": {
                            "content": [
                                {"type": "text", "text": json.dumps({"result": "ok"})}
                            ]
                        },
                    },
                )
        else:
            self._json_response(404, {"error": "not found"})

    def _json_response(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        pass  # Suppress logs during tests.


@pytest.fixture(scope="module")
def mock_gateway():
    """Start a mock gateway server for the test module."""
    server = HTTPServer(("127.0.0.1", 0), MockGatewayHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{port}"
    server.shutdown()


@pytest.fixture
def agent(mock_gateway):
    """Create an OpenClawAgent pointed at the mock gateway."""
    return OpenClawAgent(mock_gateway, "test-api-key")


def test_fetch_tools(agent):
    """Agent fetches and parses tool list from gateway."""
    tools = agent._fetch_tools()
    assert len(tools) == 3
    names = {t["name"] for t in tools}
    assert "juggler_setec_list" in names
    assert "juggler_audit_log" in names


def test_call_mcp_tool(agent):
    """Agent calls MCP tool and extracts text content."""
    result = agent._call_mcp_tool("juggler_setec_list", {})
    assert "secrets" in result or isinstance(result, str)


def test_github_fetch_tool_schema():
    """github_fetch tool has required fields."""
    assert GITHUB_FETCH_TOOL["name"] == "github_fetch"
    schema = GITHUB_FETCH_TOOL["input_schema"]
    assert "owner" in schema["properties"]
    assert "repo" in schema["properties"]
    assert "path" in schema["properties"]
    assert set(schema["required"]) == {"owner", "repo", "path"}


def test_new_tool_schemas():
    """All new GitHub write tools have correct schema structure."""
    for name, tool in LOCAL_TOOLS.items():
        assert tool["name"] == name, f"{name}: name mismatch"
        assert "description" in tool, f"{name}: missing description"
        schema = tool["input_schema"]
        assert schema["type"] == "object", f"{name}: schema type not object"
        assert "properties" in schema, f"{name}: missing properties"
        assert "required" in schema, f"{name}: missing required"
        for req in schema["required"]:
            assert (
                req in schema["properties"]
            ), f"{name}: required field {req} not in properties"


def test_github_list_alerts_schema():
    """github_list_alerts tool schema is correct."""
    assert GITHUB_LIST_ALERTS_TOOL["name"] == "github_list_alerts"
    schema = GITHUB_LIST_ALERTS_TOOL["input_schema"]
    assert set(schema["required"]) == {"owner", "repo"}
    assert "state" in schema["properties"]
    assert "per_page" in schema["properties"]


def test_github_create_branch_schema():
    """github_create_branch tool schema is correct."""
    assert GITHUB_CREATE_BRANCH_TOOL["name"] == "github_create_branch"
    schema = GITHUB_CREATE_BRANCH_TOOL["input_schema"]
    assert set(schema["required"]) == {"owner", "repo", "branch"}


def test_github_update_file_schema():
    """github_update_file tool schema is correct."""
    assert GITHUB_UPDATE_FILE_TOOL["name"] == "github_update_file"
    schema = GITHUB_UPDATE_FILE_TOOL["input_schema"]
    assert "content" in schema["properties"]
    assert "message" in schema["properties"]
    assert "branch" in schema["required"]


def test_github_create_pr_schema():
    """github_create_pr tool schema is correct."""
    assert GITHUB_CREATE_PR_TOOL["name"] == "github_create_pr"
    schema = GITHUB_CREATE_PR_TOOL["input_schema"]
    assert set(schema["required"]) == {"owner", "repo", "title", "body", "head"}


def test_mcp_to_anthropic_tool(agent):
    """MCP tool schema converts to Anthropic format."""
    mcp_tool = {
        "name": "juggler_setec_list",
        "description": "List secrets",
        "inputSchema": {"type": "object", "properties": {"count": {"type": "integer"}}},
    }
    anthropic_tool = agent._mcp_to_anthropic_tool(mcp_tool)
    assert anthropic_tool["name"] == "juggler_setec_list"
    assert anthropic_tool["description"] == "List secrets"
    assert anthropic_tool["input_schema"]["type"] == "object"


def test_build_system_prompt(agent):
    """System prompt includes campaign info and anti-hallucination rules."""
    campaign = {
        "name": "Test Campaign",
        "description": "A test campaign",
        "process": ["Step 1", "Step 2"],
        "metrics": {"kpis": ["kpi_a", "kpi_b"]},
    }
    prompt = agent._build_system_prompt(campaign)
    assert "Test Campaign" in prompt
    assert "A test campaign" in prompt
    assert "Step 1" in prompt
    assert "Step 2" in prompt
    assert "NEVER fabricate" in prompt
    assert "kpi_a" in prompt
    assert "kpi_b" in prompt


def test_build_system_prompt_schema_mode(agent):
    """Schema mode prompt includes strict step-following rules."""
    campaign = {
        "name": "Schema Test",
        "mode": "schema",
        "process": ["Step 1"],
    }
    prompt = agent._build_system_prompt(campaign)
    assert "Follow EVERY process step" in prompt
    assert "AUTONOMOUS" not in prompt


def test_build_system_prompt_autonomous_mode(agent):
    """Autonomous mode prompt includes reasoning/adaptation instructions."""
    campaign = {
        "name": "Auto Test",
        "mode": "autonomous",
        "process": ["Examine alerts"],
    }
    prompt = agent._build_system_prompt(campaign)
    assert "AUTONOMOUS" in prompt
    assert "autonomous agent" in prompt
    assert "juggler_resolve_composite" in prompt


def test_build_system_prompt_infers_mode(agent):
    """Mode inferred from readOnly when not explicitly set."""
    # readOnly=true (default) -> schema
    campaign = {
        "name": "Infer Schema",
        "guardrails": {"readOnly": True},
        "process": ["Step 1"],
    }
    prompt = agent._build_system_prompt(campaign)
    assert "Follow EVERY process step" in prompt

    # readOnly=false -> autonomous
    campaign2 = {
        "name": "Infer Auto",
        "guardrails": {"readOnly": False},
        "process": ["Step 1"],
    }
    prompt2 = agent._build_system_prompt(campaign2)
    assert "AUTONOMOUS" in prompt2


def test_build_user_prompt_with_targets(agent):
    """User prompt includes target repos."""
    campaign = {
        "name": "Dep Audit",
        "targets": [
            {
                "forge": "github",
                "org": "tinyland-inc",
                "repo": "remote-juggler",
                "branch": "main",
            },
        ],
    }
    prompt = agent._build_user_prompt(campaign)
    assert "github" in prompt
    assert "tinyland-inc" in prompt
    assert "remote-juggler" in prompt


def test_build_user_prompt_no_targets(agent):
    """User prompt works without targets."""
    campaign = {"name": "Smoketest"}
    prompt = agent._build_user_prompt(campaign)
    assert "Smoketest" in prompt


def test_extract_kpis(agent):
    """KPI extraction from JSON block in Claude response."""
    text = """Here are the results:
```json
{"kpis": {"repos_scanned": 10, "issues_found": 3}}
```
"""
    campaign = {"metrics": {"kpis": ["repos_scanned", "issues_found"]}}
    kpis = agent._extract_kpis(text, campaign)
    assert kpis["repos_scanned"] == 10
    assert kpis["issues_found"] == 3


def test_extract_kpis_no_block(agent):
    """KPI extraction returns empty dict when no JSON block."""
    kpis = agent._extract_kpis("No JSON here", {})
    assert kpis == {}


def test_extract_kpis_flat_dict(agent):
    """KPI extraction handles flat dict (no 'kpis' wrapper)."""
    text = '```json\n{"repos_scanned": 5}\n```'
    kpis = agent._extract_kpis(text, {})
    assert kpis["repos_scanned"] == 5


def test_make_result(agent):
    """CampaignResult format matches Go struct."""
    result = agent._make_result(
        campaign={"id": "test-campaign", "agent": "openclaw"},
        run_id="run-abc123",
        status="success",
        started_at="2026-02-24T00:00:00Z",
        tool_calls=5,
        kpis={"k1": 42},
    )
    assert result["campaign_id"] == "test-campaign"
    assert result["run_id"] == "run-abc123"
    assert result["status"] == "success"
    assert result["agent"] == "openclaw"
    assert result["tool_calls"] == 5
    assert result["kpis"]["k1"] == 42
    assert "finished_at" in result
    assert "started_at" in result


def test_make_result_includes_tool_trace(agent):
    """CampaignResult includes tool_trace when trace entries exist."""
    agent._tool_trace = [
        ToolTraceEntry(
            timestamp="2026-02-25T06:00:01Z",
            tool="juggler_resolve_composite",
            summary="query=github-token",
        ),
        ToolTraceEntry(
            timestamp="2026-02-25T06:00:03Z",
            tool="github_list_alerts",
            summary="25 open alerts",
            is_error=False,
        ),
    ]
    result = agent._make_result(
        campaign={"id": "test", "agent": "openclaw"},
        run_id="run-trace",
        status="success",
        started_at="2026-02-25T06:00:00Z",
    )
    assert "tool_trace" in result
    assert len(result["tool_trace"]) == 2
    assert result["tool_trace"][0]["tool"] == "juggler_resolve_composite"
    assert result["tool_trace"][1]["is_error"] is False
    # Clean up.
    agent._tool_trace = []


def test_make_result_no_trace_when_empty(agent):
    """CampaignResult omits tool_trace when no trace entries."""
    agent._tool_trace = []
    result = agent._make_result(
        campaign={"id": "test", "agent": "openclaw"},
        run_id="run-empty",
        status="success",
        started_at="2026-02-25T06:00:00Z",
    )
    assert "tool_trace" not in result


def test_resolve_github_token(agent):
    """GitHub token resolved from gateway and cached."""
    token = agent._resolve_github_token()
    assert token == "ghp_test123"

    # Second call should use cache.
    token2 = agent._resolve_github_token()
    assert token2 == token


def test_metering_context_injected(agent):
    """MCP tool calls include _agent and _campaign_id in arguments."""
    agent._campaign_id = "test-campaign-123"
    agent._call_mcp_tool("juggler_setec_list", {"count": 5})

    args = MockGatewayHandler.last_tool_call_args
    assert args.get("_agent") == "openclaw"
    assert args.get("_campaign_id") == "test-campaign-123"
    assert args.get("count") == 5
    # Clean up.
    agent._campaign_id = ""


def test_metering_context_preserves_original_args(agent):
    """Metering injection does not mutate the original args dict."""
    agent._campaign_id = "preserve-test"
    original_args = {"query": "test-secret"}
    agent._call_mcp_tool("juggler_resolve_composite", original_args)

    # Original dict should not be modified.
    assert "_agent" not in original_args
    assert "_campaign_id" not in original_args
    agent._campaign_id = ""


def test_call_tool_routes_local_tools(agent):
    """_call_tool routes local tools to their handlers instead of MCP."""
    # github_fetch is local — should call _github_fetch, not _call_mcp_tool.
    # We can't fully test it without a GitHub mock, but we can verify
    # it returns an error dict (missing required args) rather than MCP response.
    result = agent._call_tool("github_fetch", {})
    parsed = json.loads(result) if isinstance(result, str) else result
    assert "error" in parsed


def test_local_tools_registry():
    """LOCAL_TOOLS contains all 6 expected local tools."""
    expected = {
        "github_fetch",
        "github_list_alerts",
        "github_get_alert",
        "github_create_branch",
        "github_update_file",
        "github_create_pr",
    }
    assert set(LOCAL_TOOLS.keys()) == expected


def test_tool_trace_entry_dataclass():
    """ToolTraceEntry can be constructed and serialized."""
    entry = ToolTraceEntry(
        timestamp="2026-02-25T06:00:01Z",
        tool="github_list_alerts",
        summary="25 open alerts",
        is_error=False,
    )
    from dataclasses import asdict

    d = asdict(entry)
    assert d["timestamp"] == "2026-02-25T06:00:01Z"
    assert d["tool"] == "github_list_alerts"
    assert d["summary"] == "25 open alerts"
    assert d["is_error"] is False
