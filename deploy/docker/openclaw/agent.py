"""OpenClaw AI agent: Claude-powered campaign execution via rj-gateway MCP tools."""

import base64
import json
import logging
import time
from typing import Any

import anthropic
import httpx

log = logging.getLogger("openclaw.agent")

# Local tool definition for github_fetch (not an MCP tool).
GITHUB_FETCH_TOOL = {
    "name": "github_fetch",
    "description": (
        "Fetch a file from a GitHub repository. Uses the GitHub Contents API. "
        "Returns the file content as text. Works with any public or authorized private repo."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "owner": {
                "type": "string",
                "description": "Repository owner (user or org)",
            },
            "repo": {"type": "string", "description": "Repository name"},
            "path": {"type": "string", "description": "File path within the repo"},
            "ref": {
                "type": "string",
                "description": "Git ref (branch, tag, or commit SHA). Defaults to main.",
                "default": "main",
            },
        },
        "required": ["owner", "repo", "path"],
    },
}


class OpenClawAgent:
    """Executes campaigns using Claude tool_use loop with MCP tools via rj-gateway."""

    def __init__(
        self,
        gateway_url: str,
        anthropic_key: str,
        model: str = "claude-sonnet-4-20250514",
        base_url: str | None = None,
    ):
        self.gateway_url = gateway_url.rstrip("/")
        client_kwargs: dict = {
            "api_key": anthropic_key,
            "timeout": httpx.Timeout(120.0, connect=10.0),
        }
        if base_url:
            client_kwargs["base_url"] = base_url
        self.client = anthropic.Anthropic(**client_kwargs)
        self.model = model
        self.http = httpx.Client(timeout=60)
        self._github_token: str | None = None

    def run_campaign(self, campaign: dict, run_id: str) -> dict:
        """Execute a campaign using Claude tool_use loop.

        Returns a CampaignResult dict matching the Go struct in campaign.go.
        """
        started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        tool_calls = 0
        tool_calls_by_name: dict[str, int] = {}
        error_msg = ""

        try:
            # Fetch available tools from rj-gateway, filter to campaign's tool list.
            all_tools = self._fetch_tools()
            campaign_tool_names = set(campaign.get("tools", []))
            tools = [
                self._mcp_to_anthropic_tool(t)
                for t in all_tools
                if t["name"] in campaign_tool_names
            ]

            # Add local tools (not in gateway) if requested by campaign.
            if "github_fetch" in campaign_tool_names:
                tools.append(GITHUB_FETCH_TOOL)

            if not tools:
                return self._make_result(
                    campaign,
                    run_id,
                    "error",
                    started_at,
                    tool_calls=0,
                    error="no matching tools found in gateway",
                )

            system = self._build_system_prompt(campaign)
            user_msg = self._build_user_prompt(campaign)
            messages: list[dict[str, Any]] = [{"role": "user", "content": user_msg}]

            # Scale iteration limit based on campaign's token budget.
            ai_budget = campaign.get("guardrails", {}).get("aiApiBudget", {})
            budget_tokens = ai_budget.get("maxTokens", 50000)
            max_iterations = max(20, budget_tokens // 4000)
            max_response_tokens = 8192

            for _ in range(max_iterations):
                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=max_response_tokens,
                    system=system,
                    tools=tools,
                    messages=messages,
                )

                if response.stop_reason == "end_turn":
                    # Claude finished reasoning -- extract result.
                    final_text = self._extract_text(response)
                    kpis = self._extract_kpis(final_text, campaign)
                    return self._make_result(
                        campaign,
                        run_id,
                        "success",
                        started_at,
                        tool_calls=tool_calls,
                        kpis=kpis,
                    )

                if response.stop_reason == "tool_use":
                    tool_results = []
                    for block in response.content:
                        if block.type == "tool_use":
                            log.info("calling tool %s", block.name)
                            result = self._call_tool(block.name, block.input)
                            tool_calls += 1
                            tool_calls_by_name[block.name] = (
                                tool_calls_by_name.get(block.name, 0) + 1
                            )
                            tool_results.append(
                                {
                                    "type": "tool_result",
                                    "tool_use_id": block.id,
                                    "content": json.dumps(result)
                                    if isinstance(result, (dict, list))
                                    else str(result),
                                }
                            )

                    messages.append({"role": "assistant", "content": response.content})
                    messages.append({"role": "user", "content": tool_results})
                else:
                    # Unexpected stop reason.
                    error_msg = f"unexpected stop_reason: {response.stop_reason}"
                    break

            if not error_msg:
                error_msg = f"exceeded {max_iterations} iterations"

        except anthropic.APIError as e:
            error_msg = f"anthropic API error: {e}"
            log.error(error_msg)
        except Exception as e:
            error_msg = f"agent error: {e}"
            log.exception(error_msg)

        return self._make_result(
            campaign,
            run_id,
            "error",
            started_at,
            tool_calls=tool_calls,
            error=error_msg,
        )

    def _fetch_tools(self) -> list[dict]:
        """Fetch tool list from rj-gateway."""
        payload = {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
        resp = self.http.post(f"{self.gateway_url}/mcp", json=payload)
        resp.raise_for_status()
        data = resp.json()
        return data.get("result", {}).get("tools", [])

    def _call_tool(self, name: str, args: dict) -> Any:
        """Call a tool — local tools are handled directly, MCP tools via rj-gateway."""
        if name == "github_fetch":
            return self._github_fetch(args)
        return self._call_mcp_tool(name, args)

    def _call_mcp_tool(self, name: str, args: dict) -> Any:
        """Call an MCP tool via rj-gateway HTTP."""
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {"name": name, "arguments": args},
        }
        resp = self.http.post(f"{self.gateway_url}/mcp", json=payload)
        resp.raise_for_status()
        data = resp.json()

        if "error" in data:
            return {"error": data["error"].get("message", "unknown")}

        result = data.get("result", {})
        # Return the text content from MCP result.
        content = result.get("content", [])
        if content and isinstance(content, list):
            texts = [c.get("text", "") for c in content if c.get("type") == "text"]
            return "\n".join(texts) if texts else content
        return result

    def _resolve_github_token(self) -> str:
        """Resolve GitHub token via rj-gateway composite resolver, with caching."""
        if self._github_token:
            return self._github_token
        result = self._call_mcp_tool(
            "juggler_resolve_composite",
            {"query": "github-token"},
        )
        # Result is a text string with JSON; parse to extract the value.
        if isinstance(result, str):
            try:
                data = json.loads(result)
                self._github_token = data.get("value", result)
            except json.JSONDecodeError:
                self._github_token = result
        elif isinstance(result, dict):
            self._github_token = result.get("value", str(result))
        else:
            self._github_token = str(result)
        return self._github_token

    def _github_fetch(self, args: dict) -> str:
        """Fetch a file from GitHub using the Contents API."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        path = args.get("path", "")
        ref = args.get("ref", "main")

        if not owner or not repo or not path:
            return json.dumps({"error": "owner, repo, and path are required"})

        token = self._resolve_github_token()
        url = f"https://api.github.com/repos/{owner}/{repo}/contents/{path}"
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        params = {"ref": ref}

        try:
            resp = self.http.get(url, headers=headers, params=params)
            if resp.status_code == 404:
                return json.dumps({"error": f"not found: {owner}/{repo}/{path}@{ref}"})
            resp.raise_for_status()
            data = resp.json()

            # GitHub returns base64-encoded content for files.
            if data.get("type") == "file" and data.get("content"):
                content = base64.b64decode(data["content"]).decode(
                    "utf-8", errors="replace"
                )
                return content
            elif data.get("type") == "dir":
                # Return directory listing.
                entries = [{"name": e["name"], "type": e["type"]} for e in data]
                return json.dumps({"type": "directory", "entries": entries})
            else:
                return json.dumps(
                    {"error": f"unexpected content type: {data.get('type')}"}
                )
        except httpx.HTTPStatusError as e:
            return json.dumps(
                {
                    "error": f"GitHub API error {e.response.status_code}: {e.response.text[:200]}"
                }
            )
        except Exception as e:
            return json.dumps({"error": f"github_fetch failed: {e}"})

    def _mcp_to_anthropic_tool(self, mcp_tool: dict) -> dict:
        """Convert MCP tool schema to Anthropic tool format."""
        return {
            "name": mcp_tool["name"],
            "description": mcp_tool.get("description", ""),
            "input_schema": mcp_tool.get(
                "inputSchema", {"type": "object", "properties": {}}
            ),
        }

    def _build_system_prompt(self, campaign: dict) -> str:
        """Build system prompt from campaign definition."""
        parts = [
            "You are OpenClaw, an AI agent that executes structured campaigns using MCP tools.",
            "You have access to MCP tools via rj-gateway. Use them to accomplish the campaign objectives.",
            "",
            "CRITICAL RULES:",
            "- You MUST actually call the tools to gather real data. NEVER fabricate, estimate, or hallucinate results.",
            "- Every KPI value MUST come from actual tool call results. If a tool fails, report 0 or the error — do not guess.",
            "- Follow EVERY process step. Do not skip steps to save time.",
            "- If a tool returns an error or 404, log it and continue to the next item.",
            "",
            f"Campaign: {campaign.get('name', 'unnamed')}",
            f"Description: {campaign.get('description', '')}",
            "",
            "Process steps:",
        ]
        for i, step in enumerate(campaign.get("process", []), 1):
            parts.append(f"  {i}. {step}")

        parts.extend(
            [
                "",
                "When you are done, output a JSON block with your findings.",
                "The JSON should have a 'kpis' object with numeric values matching the campaign's KPI names.",
                "All KPI values must reflect actual data gathered from tool calls.",
                "Wrap the JSON in ```json ... ``` markers.",
            ]
        )

        # Include KPI names if available.
        metrics = campaign.get("metrics", {})
        kpi_names = metrics.get("kpis", [])
        if kpi_names:
            parts.append(f"\nExpected KPI keys: {', '.join(kpi_names)}")

        return "\n".join(parts)

    def _build_user_prompt(self, campaign: dict) -> str:
        """Build the initial user message."""
        targets = campaign.get("targets", [])
        if targets:
            target_strs = [
                f"  - {t.get('forge', '?')}/{t.get('org', '?')}/{t.get('repo', '?')} ({t.get('branch', 'main')})"
                for t in targets
            ]
            return (
                f"Execute the campaign '{campaign.get('name', '')}' against these targets:\n"
                + "\n".join(target_strs)
                + "\n\nFollow the process steps. Use the available MCP tools. "
                + "When done, output your findings as a JSON report."
            )
        return (
            f"Execute the campaign '{campaign.get('name', '')}'. "
            "Follow the process steps. Use the available MCP tools. "
            "When done, output your findings as a JSON report."
        )

    def _extract_text(self, response) -> str:
        """Extract text content from Claude response."""
        parts = []
        for block in response.content:
            if hasattr(block, "text"):
                parts.append(block.text)
        return "\n".join(parts)

    def _extract_kpis(self, text: str, campaign: dict) -> dict:
        """Extract KPIs from Claude's final response JSON block."""
        # Look for ```json ... ``` block.
        import re

        match = re.search(r"```json\s*\n?(.*?)\n?```", text, re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(1))
                if isinstance(data, dict):
                    return data.get("kpis", data)
            except json.JSONDecodeError:
                pass
        return {}

    def _make_result(
        self,
        campaign: dict,
        run_id: str,
        status: str,
        started_at: str,
        tool_calls: int = 0,
        kpis: dict | None = None,
        error: str = "",
    ) -> dict:
        """Create a CampaignResult dict matching the Go struct."""
        return {
            "campaign_id": campaign.get("id", ""),
            "run_id": run_id,
            "status": status,
            "started_at": started_at,
            "finished_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "agent": campaign.get("agent", "openclaw"),
            "kpis": kpis or {},
            "error": error,
            "tool_calls": tool_calls,
        }
