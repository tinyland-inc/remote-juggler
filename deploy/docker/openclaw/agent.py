"""OpenClaw AI agent: Claude-powered campaign execution via rj-gateway MCP tools."""

import base64
import json
import logging
import time
from dataclasses import dataclass, asdict
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

GITHUB_LIST_ALERTS_TOOL = {
    "name": "github_list_alerts",
    "description": (
        "List open code scanning (CodeQL) alerts for a repository. "
        "Returns alert number, rule ID, severity, and description."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "owner": {"type": "string", "description": "Repository owner"},
            "repo": {"type": "string", "description": "Repository name"},
            "state": {
                "type": "string",
                "description": "Alert state filter: open, closed, dismissed. Defaults to open.",
                "default": "open",
            },
            "per_page": {
                "type": "integer",
                "description": "Results per page (max 100). Defaults to 100.",
                "default": 100,
            },
        },
        "required": ["owner", "repo"],
    },
}

GITHUB_GET_ALERT_TOOL = {
    "name": "github_get_alert",
    "description": (
        "Get full details of a single code scanning alert including rule help text, "
        "location, and most recent instance."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "owner": {"type": "string", "description": "Repository owner"},
            "repo": {"type": "string", "description": "Repository name"},
            "alert_number": {
                "type": "integer",
                "description": "Alert number from github_list_alerts",
            },
        },
        "required": ["owner", "repo", "alert_number"],
    },
}

GITHUB_CREATE_BRANCH_TOOL = {
    "name": "github_create_branch",
    "description": (
        "Create a new branch from an existing ref. Uses the Git refs API. "
        "Typically used to create fix branches like sid/codeql-fix-*."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "owner": {"type": "string", "description": "Repository owner"},
            "repo": {"type": "string", "description": "Repository name"},
            "branch": {
                "type": "string",
                "description": "New branch name (without refs/heads/ prefix)",
            },
            "from_ref": {
                "type": "string",
                "description": "Source branch or SHA to branch from. Defaults to main.",
                "default": "main",
            },
        },
        "required": ["owner", "repo", "branch"],
    },
}

GITHUB_UPDATE_FILE_TOOL = {
    "name": "github_update_file",
    "description": (
        "Create or update a file in a repository via the Contents API. "
        "Automatically fetches the current file SHA for updates. "
        "Commits with the specified message and author."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "owner": {"type": "string", "description": "Repository owner"},
            "repo": {"type": "string", "description": "Repository name"},
            "path": {"type": "string", "description": "File path in the repository"},
            "content": {
                "type": "string",
                "description": "New file content (plain text, will be base64 encoded)",
            },
            "message": {"type": "string", "description": "Commit message"},
            "branch": {"type": "string", "description": "Target branch for the commit"},
            "author_name": {
                "type": "string",
                "description": "Git author name. Defaults to OpenClaw Agent.",
                "default": "OpenClaw Agent",
            },
            "author_email": {
                "type": "string",
                "description": "Git author email. Defaults to openclaw@tinyland.dev.",
                "default": "openclaw@tinyland.dev",
            },
        },
        "required": ["owner", "repo", "path", "content", "message", "branch"],
    },
}

GITHUB_CREATE_PR_TOOL = {
    "name": "github_create_pr",
    "description": (
        "Create a pull request. Returns the PR number and URL. "
        "Use after creating a branch and committing fixes."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "owner": {"type": "string", "description": "Repository owner"},
            "repo": {"type": "string", "description": "Repository name"},
            "title": {"type": "string", "description": "PR title"},
            "body": {"type": "string", "description": "PR description (markdown)"},
            "head": {"type": "string", "description": "Branch with changes"},
            "base": {
                "type": "string",
                "description": "Target branch to merge into. Defaults to main.",
                "default": "main",
            },
        },
        "required": ["owner", "repo", "title", "body", "head"],
    },
}

# Map of all local tool names to their schema dicts.
LOCAL_TOOLS = {
    "github_fetch": GITHUB_FETCH_TOOL,
    "github_list_alerts": GITHUB_LIST_ALERTS_TOOL,
    "github_get_alert": GITHUB_GET_ALERT_TOOL,
    "github_create_branch": GITHUB_CREATE_BRANCH_TOOL,
    "github_update_file": GITHUB_UPDATE_FILE_TOOL,
    "github_create_pr": GITHUB_CREATE_PR_TOOL,
}


@dataclass
class ToolTraceEntry:
    """Records a single tool invocation during campaign execution."""

    timestamp: str
    tool: str
    summary: str
    is_error: bool = False


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
        self.http = httpx.Client(
            timeout=60,
            headers={"X-Agent-Identity": "openclaw"},
        )
        self._github_token: str | None = None
        self._campaign_id: str = ""
        self._tool_trace: list[ToolTraceEntry] = []

    def run_campaign(self, campaign: dict, run_id: str) -> dict:
        """Execute a campaign using Claude tool_use loop.

        Returns a CampaignResult dict matching the Go struct in campaign.go.
        """
        started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        tool_calls = 0
        tool_calls_by_name: dict[str, int] = {}
        error_msg = ""

        self._campaign_id = campaign.get("id", "")
        self._tool_trace = []

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
            for local_name, local_schema in LOCAL_TOOLS.items():
                if local_name in campaign_tool_names:
                    tools.append(local_schema)

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

            # Per-campaign model override.
            model = campaign.get("model", self.model)

            # Scale iteration limit based on campaign's token budget.
            ai_budget = campaign.get("guardrails", {}).get("aiApiBudget", {})
            budget_tokens = ai_budget.get("maxTokens", 50000)
            max_iterations = max(20, budget_tokens // 2000)
            max_response_tokens = 8192

            for _ in range(max_iterations):
                response = self.client.messages.create(
                    model=model,
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

                            # Build tool trace entry.
                            is_error = False
                            content = (
                                json.dumps(result)
                                if isinstance(result, (dict, list))
                                else str(result)
                            )
                            if isinstance(result, dict) and "error" in result:
                                is_error = True
                            summary = content[:120] if content else "(empty)"
                            self._tool_trace.append(
                                ToolTraceEntry(
                                    timestamp=time.strftime(
                                        "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
                                    ),
                                    tool=block.name,
                                    summary=summary,
                                    is_error=is_error,
                                )
                            )

                            tool_results.append(
                                {
                                    "type": "tool_result",
                                    "tool_use_id": block.id,
                                    "content": content or "(empty response)",
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
        if name in LOCAL_TOOLS:
            handler = getattr(self, f"_{name}", None)
            if handler:
                return handler(args)
            return {"error": f"no handler for local tool: {name}"}
        return self._call_mcp_tool(name, args)

    def _call_mcp_tool(self, name: str, args: dict) -> Any:
        """Call an MCP tool via rj-gateway HTTP, injecting metering context."""
        # Inject metering context for attribution in the gateway's MeterStore.
        metered_args = dict(args)
        metered_args["_agent"] = "openclaw"
        if self._campaign_id:
            metered_args["_campaign_id"] = self._campaign_id

        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {"name": name, "arguments": metered_args},
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

    def _github_headers(self) -> dict:
        """Return standard GitHub API headers with resolved token."""
        token = self._resolve_github_token()
        return {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    def _github_fetch(self, args: dict) -> str:
        """Fetch a file from GitHub using the Contents API."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        path = args.get("path", "")
        ref = args.get("ref", "main")

        if not owner or not repo or not path:
            return json.dumps({"error": "owner, repo, and path are required"})

        headers = self._github_headers()
        url = f"https://api.github.com/repos/{owner}/{repo}/contents/{path}"
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

    def _github_list_alerts(self, args: dict) -> str:
        """List code scanning alerts for a repository."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        state = args.get("state", "open")
        per_page = args.get("per_page", 100)

        if not owner or not repo:
            return json.dumps({"error": "owner and repo are required"})

        headers = self._github_headers()
        url = f"https://api.github.com/repos/{owner}/{repo}/code-scanning/alerts"
        params = {"state": state, "per_page": per_page}

        try:
            resp = self.http.get(url, headers=headers, params=params)
            if resp.status_code == 404:
                return json.dumps(
                    {"error": "code scanning not enabled or repo not found"}
                )
            resp.raise_for_status()
            alerts = resp.json()
            summary = [
                {
                    "number": a.get("number"),
                    "rule_id": a.get("rule", {}).get("id"),
                    "severity": a.get("rule", {}).get("severity"),
                    "description": a.get("rule", {}).get("description", "")[:100],
                    "state": a.get("state"),
                    "html_url": a.get("html_url"),
                }
                for a in alerts
            ]
            return json.dumps({"total": len(alerts), "alerts": summary})
        except httpx.HTTPStatusError as e:
            return json.dumps(
                {
                    "error": f"GitHub API error {e.response.status_code}: {e.response.text[:200]}"
                }
            )
        except Exception as e:
            return json.dumps({"error": f"github_list_alerts failed: {e}"})

    def _github_get_alert(self, args: dict) -> str:
        """Get full details of a single code scanning alert."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        alert_number = args.get("alert_number")

        if not owner or not repo or not alert_number:
            return json.dumps({"error": "owner, repo, and alert_number are required"})

        headers = self._github_headers()
        url = f"https://api.github.com/repos/{owner}/{repo}/code-scanning/alerts/{alert_number}"

        try:
            resp = self.http.get(url, headers=headers)
            if resp.status_code == 404:
                return json.dumps({"error": f"alert {alert_number} not found"})
            resp.raise_for_status()
            alert = resp.json()
            return json.dumps(
                {
                    "number": alert.get("number"),
                    "state": alert.get("state"),
                    "rule": alert.get("rule"),
                    "tool": alert.get("tool", {}).get("name"),
                    "most_recent_instance": alert.get("most_recent_instance"),
                    "html_url": alert.get("html_url"),
                }
            )
        except httpx.HTTPStatusError as e:
            return json.dumps(
                {
                    "error": f"GitHub API error {e.response.status_code}: {e.response.text[:200]}"
                }
            )
        except Exception as e:
            return json.dumps({"error": f"github_get_alert failed: {e}"})

    def _github_create_branch(self, args: dict) -> str:
        """Create a new branch from an existing ref."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        branch = args.get("branch", "")
        from_ref = args.get("from_ref", "main")

        if not owner or not repo or not branch:
            return json.dumps({"error": "owner, repo, and branch are required"})

        headers = self._github_headers()

        # First, resolve the source ref to a SHA.
        ref_url = (
            f"https://api.github.com/repos/{owner}/{repo}/git/ref/heads/{from_ref}"
        )
        try:
            resp = self.http.get(ref_url, headers=headers)
            if resp.status_code == 404:
                return json.dumps({"error": f"source ref not found: {from_ref}"})
            resp.raise_for_status()
            sha = resp.json().get("object", {}).get("sha", "")
            if not sha:
                return json.dumps({"error": "could not resolve source SHA"})

            # Create the new branch.
            create_url = f"https://api.github.com/repos/{owner}/{repo}/git/refs"
            payload = {"ref": f"refs/heads/{branch}", "sha": sha}
            resp = self.http.post(create_url, headers=headers, json=payload)
            if resp.status_code == 422:
                return json.dumps({"error": f"branch already exists: {branch}"})
            resp.raise_for_status()
            return json.dumps({"branch": branch, "sha": sha, "created": True})
        except httpx.HTTPStatusError as e:
            return json.dumps(
                {
                    "error": f"GitHub API error {e.response.status_code}: {e.response.text[:200]}"
                }
            )
        except Exception as e:
            return json.dumps({"error": f"github_create_branch failed: {e}"})

    def _github_update_file(self, args: dict) -> str:
        """Create or update a file via GitHub Contents API."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        path = args.get("path", "")
        content = args.get("content", "")
        message = args.get("message", "")
        branch = args.get("branch", "")
        author_name = args.get("author_name", "OpenClaw Agent")
        author_email = args.get("author_email", "openclaw@tinyland.dev")

        if not owner or not repo or not path or not message or not branch:
            return json.dumps(
                {"error": "owner, repo, path, message, and branch are required"}
            )

        headers = self._github_headers()

        # Fetch current file SHA (needed for updates, absent for creates).
        file_sha = None
        check_url = f"https://api.github.com/repos/{owner}/{repo}/contents/{path}"
        try:
            resp = self.http.get(check_url, headers=headers, params={"ref": branch})
            if resp.status_code == 200:
                file_sha = resp.json().get("sha")
        except Exception:
            pass  # File doesn't exist yet, that's fine for creates.

        payload: dict[str, Any] = {
            "message": message,
            "content": base64.b64encode(content.encode()).decode(),
            "branch": branch,
            "author": {"name": author_name, "email": author_email},
            "committer": {"name": author_name, "email": author_email},
        }
        if file_sha:
            payload["sha"] = file_sha

        try:
            resp = self.http.put(check_url, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()
            return json.dumps(
                {
                    "path": path,
                    "sha": data.get("content", {}).get("sha", ""),
                    "commit_sha": data.get("commit", {}).get("sha", ""),
                    "committed": True,
                }
            )
        except httpx.HTTPStatusError as e:
            return json.dumps(
                {
                    "error": f"GitHub API error {e.response.status_code}: {e.response.text[:200]}"
                }
            )
        except Exception as e:
            return json.dumps({"error": f"github_update_file failed: {e}"})

    def _github_create_pr(self, args: dict) -> str:
        """Create a pull request."""
        owner = args.get("owner", "")
        repo = args.get("repo", "")
        title = args.get("title", "")
        body = args.get("body", "")
        head = args.get("head", "")
        base_branch = args.get("base", "main")

        if not owner or not repo or not title or not head:
            return json.dumps({"error": "owner, repo, title, and head are required"})

        headers = self._github_headers()
        url = f"https://api.github.com/repos/{owner}/{repo}/pulls"
        payload = {
            "title": title,
            "body": body,
            "head": head,
            "base": base_branch,
        }

        try:
            resp = self.http.post(url, headers=headers, json=payload)
            if resp.status_code == 422:
                return json.dumps(
                    {
                        "error": f"PR creation failed (branch may not exist or PR already exists): {resp.text[:200]}"
                    }
                )
            resp.raise_for_status()
            pr = resp.json()
            return json.dumps(
                {
                    "number": pr.get("number"),
                    "url": pr.get("html_url"),
                    "state": pr.get("state"),
                    "created": True,
                }
            )
        except httpx.HTTPStatusError as e:
            return json.dumps(
                {
                    "error": f"GitHub API error {e.response.status_code}: {e.response.text[:200]}"
                }
            )
        except Exception as e:
            return json.dumps({"error": f"github_create_pr failed: {e}"})

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
        """Build system prompt from campaign definition.

        Supports two modes:
        - "schema" (default): Follow process steps linearly.
        - "autonomous": Reason freely, adapt to findings.
        """
        mode = campaign.get("mode", "")
        if not mode:
            # Infer from readOnly: writable campaigns default to autonomous.
            read_only = campaign.get("guardrails", {}).get("readOnly", True)
            mode = "schema" if read_only else "autonomous"

        parts = [
            "You are OpenClaw, an AI agent that executes campaigns using MCP tools.",
            "You have access to MCP tools via rj-gateway. Use them to accomplish the campaign objectives.",
            "",
        ]

        if mode == "autonomous":
            parts.extend(
                [
                    "MODE: AUTONOMOUS",
                    "You are an autonomous agent. Reason about the problem, adapt to findings,",
                    "and decide which files to examine and what actions to take.",
                    "Use `juggler_resolve_composite` to resolve credentials when needed.",
                    "Report what you did and what needs human review.",
                    "",
                    "CRITICAL RULES:",
                    "- You MUST actually call the tools to gather real data. NEVER fabricate results.",
                    "- Every KPI value MUST come from actual tool call results.",
                    "- If a tool returns an error, adapt your approach or skip and note it.",
                    "- You may deviate from the process steps if you discover a better approach.",
                ]
            )
        else:
            parts.extend(
                [
                    "CRITICAL RULES:",
                    "- You MUST actually call the tools to gather real data. NEVER fabricate, estimate, or hallucinate results.",
                    "- Every KPI value MUST come from actual tool call results. If a tool fails, report 0 or the error — do not guess.",
                    "- Follow EVERY process step. Do not skip steps to save time.",
                    "- If a tool returns an error or 404, log it and continue to the next item.",
                ]
            )

        parts.extend(
            [
                "",
                f"Campaign: {campaign.get('name', 'unnamed')}",
                f"Description: {campaign.get('description', '')}",
                "",
                "Process steps:",
            ]
        )
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
        result: dict[str, Any] = {
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
        if self._tool_trace:
            result["tool_trace"] = [asdict(e) for e in self._tool_trace]
        return result
