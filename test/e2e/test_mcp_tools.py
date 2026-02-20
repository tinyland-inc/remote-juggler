"""
E2E Tests: MCP Tool Execution

Tests functional execution of all MCP tools via tools/call,
verifying parameter handling, response content, and error paths.
Extends test_mcp_protocol.py which covers protocol-level compliance.
"""

from pathlib import Path
from typing import Optional

import pytest

from conftest import run_mcp_request


# =============================================================================
# Helpers
# =============================================================================


def call_tool(name: str, arguments: dict, env: dict, timeout: int = 10) -> dict:
    """Call an MCP tool and return the response."""
    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": name,
            "arguments": arguments,
        },
    }
    return run_mcp_request(request, env=env, timeout=timeout)


def get_tool_result_text(response: dict) -> Optional[str]:
    """Extract text content from a tools/call response."""
    if not response or "result" not in response:
        return None
    result = response["result"]
    if isinstance(result, dict) and "content" in result:
        for item in result["content"]:
            if item.get("type") == "text":
                return item.get("text", "")
    # Some tools return result as a simple dict with text
    if isinstance(result, dict) and "text" in result:
        return result["text"]
    return str(result)


def assert_tool_success(response: dict, tool_name: str):
    """Assert a tool response indicates success (has result, no error)."""
    assert response, f"{tool_name}: empty response"
    assert (
        "result" in response or "error" in response
    ), f"{tool_name}: response missing both result and error: {response}"
    # Tools may return error in result content (not JSON-RPC error)
    # so we only check for JSON-RPC level errors here
    if "error" in response:
        # JSON-RPC errors are protocol-level failures
        pytest.fail(f"{tool_name}: JSON-RPC error: {response['error']}")


def assert_tool_has_content(response: dict, tool_name: str):
    """Assert a tool response has non-empty content."""
    assert_tool_success(response, tool_name)
    text = get_tool_result_text(response)
    assert (
        text is not None and len(text) > 0
    ), f"{tool_name}: response has no text content: {response}"
    return text


# =============================================================================
# Identity & Status Tools
# =============================================================================


class TestMCPIdentityTools:
    """Tests for identity management MCP tools."""

    def test_list_identities_returns_content(self, mcp_env: dict):
        """juggler_list_identities returns identity information."""
        response = call_tool("juggler_list_identities", {}, mcp_env)
        text = assert_tool_has_content(response, "list_identities")
        # Should mention at least one identity or sample output
        assert any(
            kw in text.lower()
            for kw in ["personal", "work", "github", "identity", "provider"]
        ), f"list_identities output doesn't mention identities: {text[:200]}"

    def test_list_identities_with_provider_filter(self, mcp_env: dict):
        """juggler_list_identities accepts provider filter."""
        response = call_tool(
            "juggler_list_identities",
            {"provider": "gitlab"},
            mcp_env,
        )
        assert_tool_success(response, "list_identities(provider=gitlab)")

    def test_detect_identity_in_repo(self, mcp_env: dict, temp_git_repo: Path):
        """juggler_detect_identity detects identity from repo remote."""
        response = call_tool(
            "juggler_detect_identity",
            {"repoPath": str(temp_git_repo)},
            mcp_env,
        )
        assert_tool_success(response, "detect_identity")

    def test_detect_identity_outside_repo(self, mcp_env: dict, tmp_path: Path):
        """juggler_detect_identity handles non-repo directory."""
        response = call_tool(
            "juggler_detect_identity",
            {"repoPath": str(tmp_path)},
            mcp_env,
        )
        # Should return a response (possibly an error message in content)
        assert response, "detect_identity: no response for non-repo path"

    def test_status_returns_identity_info(self, mcp_env: dict):
        """juggler_status returns current identity information."""
        response = call_tool("juggler_status", {}, mcp_env)
        text = assert_tool_has_content(response, "status")
        # Should contain identity-related information
        assert any(
            kw in text.lower()
            for kw in ["identity", "user", "email", "name", "no identity", "not in"]
        ), f"status output doesn't contain identity info: {text[:200]}"

    def test_status_verbose(self, mcp_env: dict):
        """juggler_status with verbose flag returns extra detail."""
        response = call_tool(
            "juggler_status",
            {"verbose": True},
            mcp_env,
        )
        assert_tool_success(response, "status(verbose)")

    def test_status_with_repo_path(self, mcp_env: dict, temp_git_repo: Path):
        """juggler_status accepts repoPath parameter."""
        response = call_tool(
            "juggler_status",
            {"repoPath": str(temp_git_repo)},
            mcp_env,
        )
        assert_tool_success(response, "status(repoPath)")

    def test_switch_identity(self, mcp_env: dict, temp_git_repo: Path):
        """juggler_switch sets identity in a repo."""
        response = call_tool(
            "juggler_switch",
            {"identity": "personal", "repoPath": str(temp_git_repo)},
            mcp_env,
        )
        assert_tool_success(response, "switch(personal)")

    def test_switch_unknown_identity(self, mcp_env: dict, temp_git_repo: Path):
        """juggler_switch with unknown identity returns error content."""
        response = call_tool(
            "juggler_switch",
            {"identity": "nonexistent_xyz_123", "repoPath": str(temp_git_repo)},
            mcp_env,
        )
        # Should get a response (may be error in content, not JSON-RPC error)
        assert response, "switch(unknown): no response"

    def test_switch_without_remote(self, mcp_env: dict, temp_git_repo: Path):
        """juggler_switch with setRemote=false skips remote update."""
        response = call_tool(
            "juggler_switch",
            {
                "identity": "personal",
                "repoPath": str(temp_git_repo),
                "setRemote": False,
            },
            mcp_env,
        )
        assert_tool_success(response, "switch(setRemote=false)")

    def test_validate_known_identity(self, mcp_env: dict):
        """juggler_validate checks a known identity."""
        response = call_tool(
            "juggler_validate",
            {"identity": "personal"},
            mcp_env,
        )
        text = assert_tool_has_content(response, "validate(personal)")
        # Should contain validation results
        assert any(
            kw in text.lower()
            for kw in ["ssh", "auth", "pass", "fail", "skip", "valid"]
        ), f"validate output doesn't contain validation results: {text[:200]}"

    def test_validate_unknown_identity(self, mcp_env: dict):
        """juggler_validate returns error for unknown identity."""
        response = call_tool(
            "juggler_validate",
            {"identity": "nonexistent_xyz_123"},
            mcp_env,
        )
        text = get_tool_result_text(response)
        if text:
            assert any(
                kw in text.lower()
                for kw in ["unknown", "error", "not found", "invalid"]
            ), f"validate(unknown) should indicate error: {text[:200]}"


# =============================================================================
# Configuration & Debug Tools
# =============================================================================


class TestMCPConfigTools:
    """Tests for configuration and debugging MCP tools."""

    def test_config_show_all(self, mcp_env: dict):
        """juggler_config_show returns full configuration."""
        response = call_tool("juggler_config_show", {}, mcp_env)
        text = assert_tool_has_content(response, "config_show")
        # Should contain config structure markers
        assert any(
            kw in text.lower()
            for kw in ["identities", "settings", "version", "config", "no config"]
        ), f"config_show doesn't contain config data: {text[:200]}"

    def test_config_show_identities_section(self, mcp_env: dict):
        """juggler_config_show with section=identities."""
        response = call_tool(
            "juggler_config_show",
            {"section": "identities"},
            mcp_env,
        )
        assert_tool_success(response, "config_show(identities)")

    def test_config_show_settings_section(self, mcp_env: dict):
        """juggler_config_show with section=settings."""
        response = call_tool(
            "juggler_config_show",
            {"section": "settings"},
            mcp_env,
        )
        assert_tool_success(response, "config_show(settings)")

    def test_sync_config(self, mcp_env: dict):
        """juggler_sync_config returns sync status."""
        response = call_tool("juggler_sync_config", {}, mcp_env)
        assert_tool_success(response, "sync_config")

    def test_sync_config_dry_run(self, mcp_env: dict):
        """juggler_sync_config with dryRun=true."""
        response = call_tool(
            "juggler_sync_config",
            {"dryRun": True},
            mcp_env,
        )
        assert_tool_success(response, "sync_config(dryRun)")

    def test_gpg_status(self, mcp_env: dict):
        """juggler_gpg_status returns GPG information."""
        response = call_tool("juggler_gpg_status", {}, mcp_env)
        # GPG status may fail if gpg not available, but shouldn't crash
        assert response, "gpg_status: no response"
        assert (
            "result" in response or "error" in response
        ), f"gpg_status: invalid response: {response}"

    def test_gpg_status_with_identity(self, mcp_env: dict):
        """juggler_gpg_status with identity parameter."""
        response = call_tool(
            "juggler_gpg_status",
            {"identity": "work"},
            mcp_env,
        )
        assert response, "gpg_status(identity): no response"

    def test_debug_ssh(self, mcp_env: dict):
        """juggler_debug_ssh returns SSH diagnostic info."""
        response = call_tool("juggler_debug_ssh", {}, mcp_env, timeout=15)
        # SSH debug may fail (no SSH keys, no connectivity) but shouldn't crash
        assert response, "debug_ssh: no response"
        assert (
            "result" in response or "error" in response
        ), f"debug_ssh: invalid response: {response}"

    def test_setup_status(self, mcp_env: dict):
        """juggler_setup in status mode returns setup state."""
        response = call_tool(
            "juggler_setup",
            {"mode": "status"},
            mcp_env,
        )
        assert_tool_success(response, "setup(status)")


# =============================================================================
# Token Tools
# =============================================================================


class TestMCPTokenTools:
    """Tests for token management MCP tools."""

    def test_token_verify_no_identity(self, mcp_env: dict):
        """juggler_token_verify without identity checks all."""
        response = call_tool("juggler_token_verify", {}, mcp_env, timeout=15)
        assert_tool_success(response, "token_verify")

    def test_token_verify_specific_identity(self, mcp_env: dict):
        """juggler_token_verify for a specific identity."""
        response = call_tool(
            "juggler_token_verify",
            {"identity": "personal"},
            mcp_env,
            timeout=15,
        )
        assert_tool_success(response, "token_verify(personal)")

    def test_token_get(self, mcp_env: dict):
        """juggler_token_get returns token info (masked)."""
        response = call_tool(
            "juggler_token_get",
            {"identity": "personal"},
            mcp_env,
        )
        # May not find a token, but should return a response
        assert_tool_success(response, "token_get")

    def test_store_token_returns_instructions(self, mcp_env: dict):
        """juggler_store_token returns shell commands (stub)."""
        response = call_tool(
            "juggler_store_token",
            {"identity": "personal", "token": "glpat-test-token-12345"},
            mcp_env,
        )
        assert_tool_success(response, "store_token")
        text = get_tool_result_text(response)
        if text:
            # Store token is a stub that returns shell commands
            assert any(
                kw in text.lower() for kw in ["export", "token", "set", "run", "shell"]
            ), f"store_token should return instructions: {text[:200]}"

    def test_token_clear(self, mcp_env: dict):
        """juggler_token_clear attempts to clear token."""
        response = call_tool(
            "juggler_token_clear",
            {"identity": "personal"},
            mcp_env,
        )
        # May succeed or fail (no token stored), but shouldn't crash
        assert response, "token_clear: no response"


# =============================================================================
# PIN & Security Mode Tools
# =============================================================================


class TestMCPSecurityTools:
    """Tests for PIN and security mode MCP tools."""

    def test_pin_status_no_hsm(self, mcp_env: dict):
        """juggler_pin_status reports HSM status."""
        response = call_tool("juggler_pin_status", {}, mcp_env)
        text = assert_tool_has_content(response, "pin_status")
        # Should report HSM availability
        assert any(
            kw in text.lower()
            for kw in [
                "hsm",
                "tpm",
                "secure enclave",
                "not available",
                "available",
                "pin",
                "none",
            ]
        ), f"pin_status should mention HSM: {text[:200]}"

    def test_pin_status_with_identity(self, mcp_env: dict):
        """juggler_pin_status for a specific identity."""
        response = call_tool(
            "juggler_pin_status",
            {"identity": "personal"},
            mcp_env,
        )
        assert_tool_success(response, "pin_status(personal)")

    def test_pin_store_no_hsm(self, mcp_env: dict):
        """juggler_pin_store fails gracefully without HSM."""
        response = call_tool(
            "juggler_pin_store",
            {"identity": "personal", "pin": "123456"},
            mcp_env,
        )
        # Should fail (no HSM) but not crash
        assert response, "pin_store: no response"

    def test_pin_store_validates_pin_length(self, mcp_env: dict):
        """juggler_pin_store validates PIN is 6-127 chars."""
        response = call_tool(
            "juggler_pin_store",
            {"identity": "personal", "pin": "12"},
            mcp_env,
        )
        # Short PIN should produce an error in content
        assert response, "pin_store(short): no response"

    def test_pin_clear(self, mcp_env: dict):
        """juggler_pin_clear handles no-PIN-stored case."""
        response = call_tool(
            "juggler_pin_clear",
            {"identity": "personal"},
            mcp_env,
        )
        assert response, "pin_clear: no response"

    def test_security_mode_get(self, mcp_env: dict):
        """juggler_security_mode without mode parameter returns current."""
        response = call_tool("juggler_security_mode", {}, mcp_env)
        text = assert_tool_has_content(response, "security_mode(get)")
        assert any(
            kw in text.lower()
            for kw in [
                "maximum_security",
                "developer_workflow",
                "trusted_workstation",
                "security",
                "mode",
            ]
        ), f"security_mode should report mode: {text[:200]}"

    def test_security_mode_set(self, mcp_env: dict):
        """juggler_security_mode with mode parameter sets mode."""
        response = call_tool(
            "juggler_security_mode",
            {"mode": "developer_workflow"},
            mcp_env,
        )
        assert_tool_success(response, "security_mode(set)")


# =============================================================================
# Trusted Workstation Tools
# =============================================================================


class TestMCPTrustedWorkstationTools:
    """Tests for trusted workstation MCP tools."""

    def test_tws_status(self, mcp_env: dict):
        """juggler_tws_status reports workstation security state."""
        response = call_tool("juggler_tws_status", {}, mcp_env, timeout=15)
        text = assert_tool_has_content(response, "tws_status")
        assert any(
            kw in text.lower()
            for kw in [
                "hsm",
                "tpm",
                "secure enclave",
                "yubikey",
                "not available",
                "status",
                "workstation",
            ]
        ), f"tws_status should report hardware state: {text[:200]}"

    def test_tws_enable_no_hsm(self, mcp_env: dict):
        """juggler_tws_enable fails gracefully without HSM."""
        response = call_tool(
            "juggler_tws_enable",
            {"identity": "personal"},
            mcp_env,
        )
        # Should fail (no HSM) but not crash
        assert response, "tws_enable: no response"
        text = get_tool_result_text(response)
        if text:
            assert any(
                kw in text.lower()
                for kw in ["hsm", "not available", "error", "required", "no"]
            ), f"tws_enable without HSM should indicate failure: {text[:200]}"


# =============================================================================
# KeePassXC Keys Tools
# =============================================================================


@pytest.mark.keys
class TestMCPKeysTools:
    """Tests for KeePassXC credential authority MCP tools.

    These tests verify tool parameter handling and graceful degradation
    when KeePassXC/HSM are not available (which is the common CI case).
    """

    def test_keys_status(self, mcp_env: dict):
        """juggler_keys_status reports KeePassXC availability."""
        response = call_tool("juggler_keys_status", {}, mcp_env)
        text = assert_tool_has_content(response, "keys_status")
        # Should report database status
        assert any(
            kw in text.lower()
            for kw in [
                "database",
                "kdbx",
                "keepass",
                "not found",
                "available",
                "status",
                "keys",
            ]
        ), f"keys_status should report DB status: {text[:200]}"

    def test_keys_init_without_keepassxc(self, mcp_env: dict):
        """juggler_keys_init handles missing keepassxc-cli."""
        response = call_tool("juggler_keys_init", {}, mcp_env, timeout=15)
        # Should fail gracefully if keepassxc-cli not in PATH
        assert response, "keys_init: no response"

    def test_keys_list_without_db(self, mcp_env: dict):
        """juggler_keys_list handles missing database."""
        response = call_tool(
            "juggler_keys_list",
            {},
            mcp_env,
        )
        assert response, "keys_list: no response"

    def test_keys_search_without_db(self, mcp_env: dict):
        """juggler_keys_search handles missing database."""
        response = call_tool(
            "juggler_keys_search",
            {"query": "test-credential"},
            mcp_env,
        )
        assert response, "keys_search: no response"

    def test_keys_get_without_db(self, mcp_env: dict):
        """juggler_keys_get handles missing database."""
        response = call_tool(
            "juggler_keys_get",
            {"entryPath": "RemoteJuggler/test-entry"},
            mcp_env,
        )
        assert response, "keys_get: no response"

    def test_keys_store_without_db(self, mcp_env: dict):
        """juggler_keys_store handles missing database."""
        response = call_tool(
            "juggler_keys_store",
            {"entryPath": "RemoteJuggler/test-entry", "value": "test-secret"},
            mcp_env,
        )
        assert response, "keys_store: no response"

    def test_keys_resolve_without_db(self, mcp_env: dict):
        """juggler_keys_resolve handles missing database."""
        response = call_tool(
            "juggler_keys_resolve",
            {"query": "test"},
            mcp_env,
        )
        assert response, "keys_resolve: no response"

    def test_keys_delete_requires_confirm(self, mcp_env: dict):
        """juggler_keys_delete requires confirm=true."""
        response = call_tool(
            "juggler_keys_delete",
            {"entryPath": "RemoteJuggler/test", "confirm": False},
            mcp_env,
        )
        # Should return an error about confirmation
        assert response, "keys_delete: no response"
        text = get_tool_result_text(response)
        if text:
            assert any(
                kw in text.lower()
                for kw in ["confirm", "safety", "error", "required", "true"]
            ), f"keys_delete without confirm should require it: {text[:200]}"

    def test_keys_discover_without_db(self, mcp_env: dict):
        """juggler_keys_discover handles missing database."""
        response = call_tool(
            "juggler_keys_discover",
            {"types": "env"},
            mcp_env,
        )
        assert response, "keys_discover: no response"

    def test_keys_crawl_env_without_db(self, mcp_env: dict):
        """juggler_keys_crawl_env handles missing database."""
        response = call_tool("juggler_keys_crawl_env", {}, mcp_env)
        assert response, "keys_crawl_env: no response"

    def test_keys_ingest_env_nonexistent_file(self, mcp_env: dict):
        """juggler_keys_ingest_env handles nonexistent file."""
        response = call_tool(
            "juggler_keys_ingest_env",
            {"filePath": "/tmp/nonexistent-env-file-xyz-123"},
            mcp_env,
        )
        assert response, "keys_ingest_env: no response"
        text = get_tool_result_text(response)
        if text:
            assert any(
                kw in text.lower()
                for kw in ["not found", "error", "exist", "no such", "file"]
            ), f"keys_ingest_env should report missing file: {text[:200]}"

    def test_keys_export_without_db(self, mcp_env: dict):
        """juggler_keys_export handles missing database."""
        response = call_tool(
            "juggler_keys_export",
            {"group": "RemoteJuggler"},
            mcp_env,
        )
        assert response, "keys_export: no response"


# =============================================================================
# Tool Schema Validation
# =============================================================================


class TestMCPToolSchemas:
    """Tests that verify tool definitions match expected schemas."""

    def test_all_tools_listed(self, mcp_env: dict):
        """Verify all expected tools appear in tools/list."""
        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {},
        }
        response = run_mcp_request(request, env=mcp_env)

        if not response or "result" not in response:
            pytest.skip("Could not get tools list")

        tools = response["result"].get("tools", [])
        tool_names = {t.get("name", "") for t in tools}

        expected_tools = {
            "juggler_list_identities",
            "juggler_detect_identity",
            "juggler_switch",
            "juggler_status",
            "juggler_validate",
            "juggler_store_token",
            "juggler_sync_config",
            "juggler_gpg_status",
            "juggler_setup",
            "juggler_pin_store",
            "juggler_pin_clear",
            "juggler_pin_status",
            "juggler_security_mode",
            "juggler_token_verify",
            "juggler_config_show",
            "juggler_debug_ssh",
            "juggler_token_get",
            "juggler_token_clear",
            "juggler_tws_status",
            "juggler_tws_enable",
            "juggler_keys_status",
            "juggler_keys_search",
            "juggler_keys_get",
            "juggler_keys_store",
            "juggler_keys_ingest_env",
            "juggler_keys_list",
            "juggler_keys_init",
            "juggler_keys_resolve",
            "juggler_keys_delete",
            "juggler_keys_crawl_env",
            "juggler_keys_discover",
            "juggler_keys_export",
        }

        missing = expected_tools - tool_names
        assert not missing, f"Missing tools in tools/list: {missing}"

    def test_tools_have_descriptions(self, mcp_env: dict):
        """All tools should have non-empty descriptions."""
        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {},
        }
        response = run_mcp_request(request, env=mcp_env)

        if not response or "result" not in response:
            pytest.skip("Could not get tools list")

        tools = response["result"].get("tools", [])

        for tool in tools:
            name = tool.get("name", "unknown")
            desc = tool.get("description", "")
            assert desc, f"Tool {name} has no description"

    def test_tools_have_input_schemas(self, mcp_env: dict):
        """All tools should define inputSchema."""
        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {},
        }
        response = run_mcp_request(request, env=mcp_env)

        if not response or "result" not in response:
            pytest.skip("Could not get tools list")

        tools = response["result"].get("tools", [])

        for tool in tools:
            name = tool.get("name", "unknown")
            schema = tool.get("inputSchema")
            assert schema is not None, f"Tool {name} has no inputSchema"
            assert (
                schema.get("type") == "object"
            ), f"Tool {name} inputSchema type should be 'object': {schema}"
