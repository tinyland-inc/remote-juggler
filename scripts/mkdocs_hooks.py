#!/usr/bin/env python3
"""
MkDocs hooks for RemoteJuggler documentation.

This module provides hooks that run during MkDocs build:
- on_post_build: Generate llms.txt and llms-full.txt after site build
"""

import subprocess
import sys
from pathlib import Path


def on_post_build(config, **kwargs):
    """Generate llms.txt files after MkDocs build completes.

    This hook runs the generate-llms-txt.py script to create:
    - llms.txt: Navigation index with descriptions
    - llms-full.txt: Full documentation content

    Args:
        config: MkDocs configuration object
        **kwargs: Additional arguments from MkDocs
    """
    # Determine paths
    docs_dir = Path(config.get('docs_dir', 'docs'))
    site_dir = Path(config.get('site_dir', 'site'))
    site_url = config.get('site_url', '')

    # Path to generator script (relative to project root)
    script_path = Path(__file__).parent / 'generate-llms-txt.py'

    if not script_path.exists():
        print(f"Warning: llms.txt generator not found at {script_path}")
        return

    # Build command
    cmd = [
        sys.executable,
        str(script_path),
        '--docs-dir', str(docs_dir),
        '--output-dir', str(site_dir),
    ]

    if site_url:
        cmd.extend(['--site-url', site_url])

    print(f"\nGenerating llms.txt files...")

    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True
        )
        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
    except subprocess.CalledProcessError as e:
        print(f"Warning: llms.txt generation failed: {e}")
        if e.stdout:
            print(e.stdout)
        if e.stderr:
            print(e.stderr, file=sys.stderr)
    except Exception as e:
        print(f"Warning: Could not run llms.txt generator: {e}")
