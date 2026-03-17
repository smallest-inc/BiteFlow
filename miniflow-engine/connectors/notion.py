"""Notion connector — uses notion-client SDK."""

from __future__ import annotations

import logging

log = logging.getLogger("connectors.notion")

TOOLS = [
    {"type": "function", "function": {
        "name": "notion_search",
        "description": "Search pages and databases in Notion",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "limit": {"type": "integer", "default": 5},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "notion_read_page",
        "description": "Read the content of a Notion page",
        "parameters": {"type": "object", "properties": {
            "page_id": {"type": "string"},
        }, "required": ["page_id"]},
    }},
    {"type": "function", "function": {
        "name": "notion_create_page",
        "description": "Create a new Notion page",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"},
            "content": {"type": "string"},
            "parent_id": {"type": "string", "description": "Parent page or database ID (optional)"},
        }, "required": ["title", "content"]},
    }},
    {"type": "function", "function": {
        "name": "notion_update_page",
        "description": "Append content to an existing Notion page",
        "parameters": {"type": "object", "properties": {
            "page_id": {"type": "string"},
            "content": {"type": "string"},
        }, "required": ["page_id", "content"]},
    }},
]


def _client(token: dict):
    from notion_client import Client
    return Client(auth=token["access_token"])


def _extract_title(page: dict) -> str:
    props = page.get("properties", {})
    for key in ("title", "Title", "Name"):
        prop = props.get(key, {})
        title_arr = prop.get("title", [])
        if title_arr:
            return "".join(t.get("plain_text", "") for t in title_arr)
    return page.get("id", "Untitled")


def _blocks_to_text(blocks: list) -> str:
    lines = []
    for b in blocks:
        btype = b.get("type", "")
        content = b.get(btype, {})
        rich = content.get("rich_text", [])
        text = "".join(r.get("plain_text", "") for r in rich)
        if text:
            lines.append(text)
    return "\n".join(lines)


def _text_to_blocks(text: str) -> list:
    blocks = []
    for line in text.split("\n"):
        blocks.append({
            "object": "block",
            "type": "paragraph",
            "paragraph": {
                "rich_text": [{"type": "text", "text": {"content": line or " "}}]
            },
        })
    return blocks


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        client = _client(token)

        if name == "notion_search":
            res = client.search(query=args["query"], page_size=args.get("limit", 5))
            results = res.get("results", [])
            if not results:
                return True, "No results found."
            lines = [f"ID:{r['id']}  {_extract_title(r)}  (type:{r.get('object','')})" for r in results]
            return True, "\n".join(lines)

        elif name == "notion_read_page":
            page = client.pages.retrieve(page_id=args["page_id"])
            title = _extract_title(page)
            blocks_res = client.blocks.children.list(block_id=args["page_id"])
            text = _blocks_to_text(blocks_res.get("results", []))
            return True, f"# {title}\n\n{text[:3000]}"

        elif name == "notion_create_page":
            parent: dict
            if args.get("parent_id"):
                parent = {"page_id": args["parent_id"]}
            else:
                # Use workspace as parent (requires integration to have workspace access)
                parent = {"workspace": True}

            page = client.pages.create(
                parent=parent,
                properties={
                    "title": {"title": [{"type": "text", "text": {"content": args["title"]}}]}
                },
                children=_text_to_blocks(args["content"]),
            )
            return True, f"Page created: {page.get('url', page.get('id', ''))}"

        elif name == "notion_update_page":
            client.blocks.children.append(
                block_id=args["page_id"],
                children=_text_to_blocks(args["content"]),
            )
            return True, f"Content appended to page {args['page_id']}."

        return False, f"Unknown tool: {name}"

    except Exception as e:
        log.error(f"[notion/{name}] {e}")
        return False, str(e)
