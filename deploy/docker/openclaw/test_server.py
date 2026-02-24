"""Tests for OpenClaw HTTP server: health, campaign dispatch, status, concurrency."""

import json
from unittest.mock import MagicMock
from io import BytesIO

import pytest

# Patch anthropic before importing server (it's imported in agent.py).
import sys

sys.modules.setdefault("anthropic", MagicMock())

from server import AgentHandler, AgentState  # noqa: E402
from agent import OpenClawAgent  # noqa: E402


@pytest.fixture
def agent_state():
    """Create an AgentState with a mock agent."""
    mock_agent = MagicMock(spec=OpenClawAgent)
    mock_agent.run_campaign.return_value = {
        "campaign_id": "test",
        "run_id": "run-1",
        "status": "success",
        "started_at": "2026-02-24T00:00:00Z",
        "finished_at": "2026-02-24T00:01:00Z",
        "agent": "openclaw",
        "tool_calls": 3,
        "kpis": {"k1": 42},
        "error": "",
    }
    return AgentState(mock_agent)


class MockRequest:
    """Minimal mock for BaseHTTPRequestHandler."""

    def __init__(self, method, path, body=None):
        self.method = method
        self.path = path
        self.body = body or b""

    def makefile(self, *args, **kwargs):
        return BytesIO(self.body)


def make_handler(state, method, path, body=None):
    """Create an AgentHandler with mocked request/response."""
    import server as server_mod

    # Set global state.
    server_mod.state = state

    # Build raw HTTP request.
    body_bytes = body.encode() if isinstance(body, str) else (body or b"")
    request_line = f"{method} {path} HTTP/1.1\r\n"
    headers = (
        f"Content-Length: {len(body_bytes)}\r\nContent-Type: application/json\r\n\r\n"
    )
    raw = (request_line + headers).encode() + body_bytes

    from io import BytesIO

    class FakeSocket:
        def __init__(self, data):
            self.stream = BytesIO(data)
            self.response = BytesIO()

        def makefile(self, mode, *args, **kwargs):
            if "r" in mode:
                return self.stream
            return self.response

        def sendall(self, data):
            self.response.write(data)

    sock = FakeSocket(raw)
    handler = AgentHandler(sock, ("127.0.0.1", 9999), None)
    return handler, sock


def parse_response(sock):
    """Parse the HTTP response from the fake socket."""
    sock.response.seek(0)
    raw = sock.response.read().decode(errors="replace")
    # Split headers from body.
    parts = raw.split("\r\n\r\n", 1)
    if len(parts) == 2:
        body = parts[1]
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return body
    return raw


def test_health_endpoint(agent_state):
    """GET /health returns status and agent info."""
    _, sock = make_handler(agent_state, "GET", "/health")
    data = parse_response(sock)
    assert data["status"] == "ok"
    assert data["agent"] == "openclaw"
    assert data["scaffold"] is False


def test_status_idle(agent_state):
    """GET /status returns idle when no campaign running."""
    _, sock = make_handler(agent_state, "GET", "/status")
    data = parse_response(sock)
    assert data["status"] == "idle"


def test_campaign_dispatch(agent_state):
    """POST /campaign accepts and starts campaign."""
    campaign_payload = json.dumps(
        {
            "campaign": {
                "id": "test-campaign",
                "name": "Test",
                "agent": "openclaw",
                "tools": ["juggler_setec_list"],
                "process": ["Step 1"],
                "guardrails": {"maxDuration": "2m"},
                "outputs": {"setecKey": "test"},
                "metrics": {"kpis": ["k1"]},
            },
            "run_id": "run-test-1",
        }
    )
    _, sock = make_handler(agent_state, "POST", "/campaign", campaign_payload)
    data = parse_response(sock)
    assert data["status"] == "accepted"
    assert data["campaign_id"] == "test-campaign"
    assert data["run_id"] == "run-test-1"


def test_campaign_already_running(agent_state):
    """POST /campaign returns 409 if campaign already running."""
    # Simulate a running campaign.
    agent_state.start_campaign({"id": "existing"}, "run-1")

    campaign_payload = json.dumps(
        {
            "campaign": {"id": "new-campaign"},
            "run_id": "run-2",
        }
    )
    _, sock = make_handler(agent_state, "POST", "/campaign", campaign_payload)
    raw = sock.response.getvalue().decode(errors="replace")
    assert "409" in raw


def test_campaign_missing_field(agent_state):
    """POST /campaign returns 400 if campaign field missing."""
    _, sock = make_handler(
        agent_state, "POST", "/campaign", json.dumps({"run_id": "x"})
    )
    raw = sock.response.getvalue().decode(errors="replace")
    assert "400" in raw


def test_agent_state_lifecycle():
    """AgentState tracks campaign lifecycle correctly."""
    mock_agent = MagicMock(spec=OpenClawAgent)
    state = AgentState(mock_agent)

    # Initially idle.
    status = state.get_status()
    assert status["status"] == "idle"
    assert status["last_result"] is None

    # Start campaign.
    ok = state.start_campaign({"id": "camp-1"}, "run-1")
    assert ok is True
    assert state.get_status()["status"] == "running"

    # Can't start another while running.
    ok = state.start_campaign({"id": "camp-2"}, "run-2")
    assert ok is False

    # Finish campaign.
    state.finish_campaign({"status": "success", "tool_calls": 5})
    status = state.get_status()
    assert status["status"] == "success"
    assert status["last_result"]["tool_calls"] == 5

    # Can start another after finishing.
    ok = state.start_campaign({"id": "camp-3"}, "run-3")
    assert ok is True
