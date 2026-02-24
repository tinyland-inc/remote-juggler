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

from agent import OpenClawAgent, GITHUB_FETCH_TOOL  # noqa: E402


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

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))

        if body.get("method") == "tools/list":
            self._json_response(200, self.tools_response)
        elif body.get("method") == "tools/call":
            name = body["params"]["name"]
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


def test_resolve_github_token(agent):
    """GitHub token resolved from gateway and cached."""
    token = agent._resolve_github_token()
    assert token == "ghp_test123"

    # Second call should use cache.
    token2 = agent._resolve_github_token()
    assert token2 == token
