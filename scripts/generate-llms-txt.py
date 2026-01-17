#!/usr/bin/env python3
"""
Generate llms.txt and llms-full.txt from MkDocs documentation.

Reads frontmatter from all docs/*.md files, generates:
- llms.txt: Navigation index with descriptions
- llms-full.txt: Full content concatenation

Based on the llms.txt specification from llmstxt.org
"""

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class DocPage:
    """Represents a documentation page with metadata."""
    path: Path
    title: str
    description: str
    category: str
    priority: int
    content: str
    keywords: list = field(default_factory=list)
    tools: list = field(default_factory=list)


def parse_frontmatter(content: str) -> tuple[dict, str]:
    """Extract YAML frontmatter and body from markdown.

    Args:
        content: Raw markdown file content

    Returns:
        Tuple of (metadata dict, body content)
    """
    if not content.startswith('---'):
        return {}, content

    # Find the closing ---
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)$', content, re.DOTALL)
    if not match:
        return {}, content

    frontmatter_str = match.group(1)
    body = match.group(2).strip()

    # Parse YAML manually (avoid dependency on pyyaml for simple cases)
    meta = {}
    current_key = None
    current_list = None

    for line in frontmatter_str.split('\n'):
        # Skip empty lines and comments
        if not line.strip() or line.strip().startswith('#'):
            continue

        # Check for list item
        if line.startswith('  - ') and current_key:
            if current_list is None:
                current_list = []
            current_list.append(line[4:].strip().strip('"\''))
            meta[current_key] = current_list
            continue

        # Check for key: value
        if ':' in line:
            key, _, value = line.partition(':')
            key = key.strip()
            value = value.strip().strip('"\'')

            if value:
                meta[key] = value
                current_key = None
                current_list = None
            else:
                # Value on next lines (list or multiline)
                current_key = key
                current_list = None

    return meta, body


def clean_markdown(content: str) -> str:
    """Clean markdown content for llms-full.txt.

    Removes frontmatter, normalizes whitespace, and ensures consistent formatting.
    """
    # Remove frontmatter if present
    _, body = parse_frontmatter(content)

    # Normalize line endings
    body = body.replace('\r\n', '\n')

    # Remove excessive blank lines (more than 2)
    body = re.sub(r'\n{3,}', '\n\n', body)

    return body.strip()


def get_relative_url(path: Path, docs_dir: Path) -> str:
    """Convert file path to relative URL path."""
    rel_path = path.relative_to(docs_dir)
    # Convert to URL path (remove .md extension, handle index files)
    url_path = str(rel_path).replace('.md', '/')
    if url_path.endswith('/index/'):
        url_path = url_path[:-6]  # Remove 'index/'
    return url_path


def discover_pages(docs_dir: Path) -> list[DocPage]:
    """Discover and parse all markdown pages in docs directory.

    Args:
        docs_dir: Path to docs directory

    Returns:
        List of DocPage objects with parsed metadata
    """
    pages = []

    for md_file in sorted(docs_dir.rglob('*.md')):
        try:
            content = md_file.read_text(encoding='utf-8')
        except Exception as e:
            print(f"Warning: Could not read {md_file}: {e}", file=sys.stderr)
            continue

        meta, body = parse_frontmatter(content)

        # Extract metadata with defaults
        title = meta.get('title', md_file.stem.replace('-', ' ').title())
        description = meta.get('description', '')
        category = meta.get('category', 'reference')
        priority = int(meta.get('llm_priority', 5))
        keywords = meta.get('keywords', [])
        tools = meta.get('tools', [])

        # Skip pages without descriptions for llms.txt (but include in full)
        if not description:
            # Try to extract first paragraph as description
            first_para = re.match(r'^#[^\n]*\n+([^\n#]+)', body)
            if first_para:
                description = first_para.group(1).strip()[:200]

        page = DocPage(
            path=md_file,
            title=title,
            description=description,
            category=category,
            priority=priority,
            content=body,
            keywords=keywords if isinstance(keywords, list) else [keywords],
            tools=tools if isinstance(tools, list) else [tools],
        )
        pages.append(page)

    return pages


def generate_llms_txt(pages: list[DocPage], site_url: str, docs_dir: Path) -> str:
    """Generate llms.txt navigation index.

    Args:
        pages: List of DocPage objects
        site_url: Base URL for the documentation site
        docs_dir: Path to docs directory

    Returns:
        Content for llms.txt file
    """
    output = []
    output.append("# RemoteJuggler")
    output.append("")
    output.append("> Backend-agnostic git identity management with MCP/ACP agent protocol support. "
                  "Seamlessly switch between GitLab, GitHub, and Bitbucket identities with "
                  "automatic credential resolution, GPG signing, and IDE integration.")
    output.append("")
    output.append("RemoteJuggler enables developers to manage multiple git identities across "
                  "providers. It integrates with AI coding assistants via MCP (Model Context Protocol) "
                  "and JetBrains IDEs via ACP (Agent Communication Protocol).")
    output.append("")

    # Category definitions with display order
    categories = {
        'api': ('## MCP Tools & API', []),
        'config': ('## Configuration', []),
        'cli': ('## CLI Reference', []),
        'operations': ('## Operations', []),
        'reference': ('## Reference', []),
    }

    optional_pages = []

    # Sort pages by priority then title
    sorted_pages = sorted(pages, key=lambda p: (p.priority, p.title))

    for page in sorted_pages:
        # Skip index pages and pages without descriptions
        if page.path.name == 'index.md' or not page.description:
            continue

        url_path = get_relative_url(page.path, docs_dir)
        full_url = f"{site_url.rstrip('/')}/{url_path.lstrip('/')}"

        # Priority 4-5 goes to optional section
        if page.priority >= 4:
            optional_pages.append(f"- [{page.title}]({full_url}): {page.description}")
            continue

        # Add to appropriate category
        cat = page.category if page.category in categories else 'reference'
        categories[cat][1].append(f"- [{page.title}]({full_url}): {page.description}")

    # Output categories in order
    for cat in ['api', 'config', 'cli', 'operations', 'reference']:
        header, links = categories[cat]
        if links:
            output.append(header)
            output.extend(links)
            output.append("")

    # Optional section
    if optional_pages:
        output.append("## Optional")
        output.extend(optional_pages)
        output.append("")

    return "\n".join(output)


def generate_llms_full_txt(pages: list[DocPage]) -> str:
    """Generate llms-full.txt with complete documentation content.

    Args:
        pages: List of DocPage objects

    Returns:
        Content for llms-full.txt file
    """
    output = []
    output.append("# RemoteJuggler - Complete Documentation")
    output.append("")
    output.append("> Backend-agnostic git identity management with MCP/ACP agent protocol support.")
    output.append("")

    # Sort by priority then title for logical reading order
    sorted_pages = sorted(pages, key=lambda p: (p.priority, p.title))

    for page in sorted_pages:
        # Skip index pages (they're usually just navigation)
        if page.path.name == 'index.md':
            continue

        output.append(f"## {page.title}")
        output.append("")

        # Add metadata as context
        if page.description:
            output.append(f"*{page.description}*")
            output.append("")

        output.append(page.content)
        output.append("")
        output.append("---")
        output.append("")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(
        description='Generate llms.txt and llms-full.txt from MkDocs documentation'
    )
    parser.add_argument(
        '--docs-dir',
        type=Path,
        default=Path('docs'),
        help='Path to docs directory (default: docs)'
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('site'),
        help='Output directory for generated files (default: site)'
    )
    parser.add_argument(
        '--site-url',
        default='https://tinyland.gitlab.io/projects/remote-juggler',
        help='Base URL for the documentation site'
    )
    parser.add_argument(
        '--validate-only',
        action='store_true',
        help='Only validate frontmatter, do not generate files'
    )

    args = parser.parse_args()

    # Validate docs directory
    if not args.docs_dir.exists():
        print(f"Error: docs directory not found: {args.docs_dir}", file=sys.stderr)
        sys.exit(1)

    # Discover pages
    pages = discover_pages(args.docs_dir)
    print(f"Discovered {len(pages)} documentation pages")

    # Report pages missing frontmatter
    missing_frontmatter = [p for p in pages if not p.description]
    if missing_frontmatter:
        print(f"\nWarning: {len(missing_frontmatter)} pages missing description:")
        for p in missing_frontmatter[:10]:
            print(f"  - {p.path.relative_to(args.docs_dir)}")
        if len(missing_frontmatter) > 10:
            print(f"  ... and {len(missing_frontmatter) - 10} more")

    if args.validate_only:
        # Validation mode - just report stats
        categories = {}
        for p in pages:
            categories[p.category] = categories.get(p.category, 0) + 1
        print(f"\nCategories: {categories}")

        priorities = {}
        for p in pages:
            priorities[p.priority] = priorities.get(p.priority, 0) + 1
        print(f"Priorities: {priorities}")

        sys.exit(0 if not missing_frontmatter else 1)

    # Create output directory
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Generate llms.txt
    llms_txt = generate_llms_txt(pages, args.site_url, args.docs_dir)
    llms_txt_path = args.output_dir / 'llms.txt'
    llms_txt_path.write_text(llms_txt, encoding='utf-8')
    print(f"\nGenerated: {llms_txt_path} ({len(llms_txt)} bytes)")

    # Generate llms-full.txt
    llms_full_txt = generate_llms_full_txt(pages)
    llms_full_txt_path = args.output_dir / 'llms-full.txt'
    llms_full_txt_path.write_text(llms_full_txt, encoding='utf-8')
    print(f"Generated: {llms_full_txt_path} ({len(llms_full_txt)} bytes)")

    # Warn if llms-full.txt is too large for most LLM contexts
    if len(llms_full_txt) > 102400:
        print(f"\nWarning: llms-full.txt exceeds 100KB ({len(llms_full_txt)} bytes)")
        print("  This may not fit in some LLM context windows")


if __name__ == '__main__':
    main()
