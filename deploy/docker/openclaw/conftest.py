"""Pytest configuration for OpenClaw tests.

Ensures anthropic and httpx are mockable when not installed locally.
Tests are designed to run in Docker (with real deps) or locally (with mocks).
"""

import sys
from unittest.mock import MagicMock

# Mock heavy dependencies if not available (allows running outside Docker).
for mod in ["anthropic", "httpx"]:
    if mod not in sys.modules:
        try:
            __import__(mod)
        except ImportError:
            sys.modules[mod] = MagicMock()
