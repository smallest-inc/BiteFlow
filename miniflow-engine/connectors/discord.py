"""Discord connector — uses user OAuth2 token via REST API."""

from __future__ import annotations

import logging

import httpx

log = logging.getLogger("connectors.discord")

DISCORD_API = "https://discord.com/api/v10"

TOOLS = [
    {"type": "function", "function": {
        "name": "discord_list_servers",
        "description": "List Discord servers (guilds) the user is in",
        "parameters": {"type": "object", "properties": {}, "required": []},
    }},
    {"type": "function", "function": {
        "name": "discord_read_channel",
        "description": "Read recent messages from a Discord channel (requires bot token for guild channels)",
        "parameters": {"type": "object", "properties": {
            "channel_id": {"type": "string"},
            "limit": {"type": "integer", "default": 10},
        }, "required": ["channel_id"]},
    }},
    {"type": "function", "function": {
        "name": "discord_send_message",
        "description": "Send a message to a Discord channel",
        "parameters": {"type": "object", "properties": {
            "channel_id": {"type": "string"},
            "text": {"type": "string"},
        }, "required": ["channel_id", "text"]},
    }},
]


def _headers(token: dict) -> dict:
    return {"Authorization": f"Bearer {token['access_token']}"}


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        headers = _headers(token)

        if name == "discord_list_servers":
            res = httpx.get(f"{DISCORD_API}/users/@me/guilds", headers=headers, timeout=10)
            res.raise_for_status()
            guilds = res.json()
            if not guilds:
                return True, "No servers found."
            return True, "\n".join(f"ID:{g['id']}  {g['name']}" for g in guilds)

        elif name == "discord_read_channel":
            res = httpx.get(
                f"{DISCORD_API}/channels/{args['channel_id']}/messages",
                headers=headers,
                params={"limit": args.get("limit", 10)},
                timeout=10,
            )
            res.raise_for_status()
            msgs = res.json()
            if not msgs:
                return True, "No messages."
            lines = [f"{m['author']['username']}: {m['content']}" for m in reversed(msgs)]
            return True, "\n".join(lines)

        elif name == "discord_send_message":
            res = httpx.post(
                f"{DISCORD_API}/channels/{args['channel_id']}/messages",
                headers=headers,
                json={"content": args["text"]},
                timeout=10,
            )
            res.raise_for_status()
            return True, "Message sent."

        return False, f"Unknown tool: {name}"

    except httpx.HTTPStatusError as e:
        log.error(f"[discord/{name}] HTTP {e.response.status_code}: {e.response.text}")
        return False, f"Discord API error {e.response.status_code}: {e.response.text[:200]}"
    except Exception as e:
        log.error(f"[discord/{name}] {e}")
        return False, str(e)
