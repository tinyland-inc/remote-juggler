"""HexStrike agent HTTP server: health, campaign dispatch, and status."""

import json
import logging
import os
import threading
import time
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler

from agent import HexStrikeAgent

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
log = logging.getLogger("hexstrike.server")


class AgentState:
    """Shared state between HTTP handler and background campaign execution."""

    def __init__(self, agent: HexStrikeAgent):
        self.agent = agent
        self.lock = threading.Lock()
        self.current_campaign_id: str | None = None
        self.current_run_id: str | None = None
        self.current_status: str = "idle"  # idle, running, completed, error
        self.last_result: dict | None = None

    def start_campaign(self, campaign: dict, run_id: str) -> bool:
        """Try to start a campaign. Returns False if one is already running."""
        with self.lock:
            if self.current_status == "running":
                return False
            self.current_campaign_id = campaign.get("id", "")
            self.current_run_id = run_id
            self.current_status = "running"
            self.last_result = None
        return True

    def finish_campaign(self, result: dict):
        with self.lock:
            self.current_status = result.get("status", "completed")
            self.last_result = result

    def get_status(self) -> dict:
        with self.lock:
            return {
                "campaign_id": self.current_campaign_id,
                "run_id": self.current_run_id,
                "status": self.current_status,
                "last_result": self.last_result,
            }


# Global state -- set in main().
state: AgentState | None = None


class AgentHandler(BaseHTTPRequestHandler):
    """HTTP handler for HexStrike agent endpoints."""

    def do_GET(self):
        if self.path == "/health":
            self._json_response(
                200,
                {
                    "status": "ok",
                    "agent": "hexstrike",
                    "scaffold": False,
                    "gateway": os.environ.get("RJ_GATEWAY_URL", ""),
                    "tools": ["nmap", "netcat", "dig", "whois"],
                },
            )
        elif self.path == "/status":
            self._json_response(200, state.get_status())
        else:
            self._json_response(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/campaign":
            self._handle_campaign()
        else:
            self._json_response(404, {"error": "not found"})

    def _handle_campaign(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._json_response(400, {"error": "invalid JSON"})
            return

        campaign = data.get("campaign")
        run_id = data.get("run_id", f"run-{uuid.uuid4().hex[:8]}")

        if not campaign:
            self._json_response(400, {"error": "missing 'campaign' field"})
            return

        if not state.start_campaign(campaign, run_id):
            self._json_response(
                409,
                {
                    "error": "campaign already running",
                    "campaign_id": state.current_campaign_id,
                },
            )
            return

        # Run campaign in background thread.
        thread = threading.Thread(
            target=self._run_campaign_bg,
            args=(campaign, run_id),
            daemon=True,
        )
        thread.start()

        self._json_response(
            202,
            {
                "status": "accepted",
                "campaign_id": campaign.get("id", ""),
                "run_id": run_id,
            },
        )

    def _run_campaign_bg(self, campaign: dict, run_id: str):
        """Execute campaign in background and update state."""
        log.info("starting campaign %s (run_id=%s)", campaign.get("id"), run_id)
        try:
            result = state.agent.run_campaign(campaign, run_id)
            log.info(
                "campaign %s completed: status=%s, tool_calls=%d",
                campaign.get("id"),
                result.get("status"),
                result.get("tool_calls", 0),
            )
        except Exception as e:
            log.exception("campaign %s failed", campaign.get("id"))
            result = {
                "campaign_id": campaign.get("id", ""),
                "run_id": run_id,
                "status": "error",
                "error": str(e),
                "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "finished_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "agent": "hexstrike",
                "tool_calls": 0,
                "kpis": {},
            }
        state.finish_campaign(result)

    def _json_response(self, status: int, data: dict):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        log.debug(format, *args)


def main():
    global state

    gateway_url = os.environ.get("RJ_GATEWAY_URL", "https://rj-gateway:443")
    anthropic_key = os.environ.get("ANTHROPIC_API_KEY", "")
    model = os.environ.get("HEXSTRIKE_MODEL", "claude-sonnet-4-20250514")
    port = int(os.environ.get("HEXSTRIKE_PORT", "8080"))

    if not anthropic_key:
        log.warning("ANTHROPIC_API_KEY not set -- campaign execution will fail")

    agent = HexStrikeAgent(gateway_url, anthropic_key, model)
    state = AgentState(agent)

    server = HTTPServer(("0.0.0.0", port), AgentHandler)
    log.info(
        "HexStrike agent listening on :%d (gateway=%s, model=%s)",
        port,
        gateway_url,
        model,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
