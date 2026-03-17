"""Slack connector."""

from __future__ import annotations

import logging

log = logging.getLogger("connectors.slack")

TOOLS = [
    {"type": "function", "function": {
        "name": "slack_send_message",
        "description": "Send a message to a Slack channel or user",
        "parameters": {"type": "object", "properties": {
            "channel": {"type": "string", "description": "#channel or @username"},
            "text": {"type": "string"},
        }, "required": ["channel", "text"]},
    }},
    {"type": "function", "function": {
        "name": "slack_search",
        "description": "Search messages in Slack",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "slack_list_channels",
        "description": "List Slack channels the user is in",
        "parameters": {"type": "object", "properties": {}, "required": []},
    }},
    {"type": "function", "function": {
        "name": "slack_read_channel",
        "description": "Read recent messages from a Slack channel",
        "parameters": {"type": "object", "properties": {
            "channel": {"type": "string"},
            "limit": {"type": "integer", "default": 10},
        }, "required": ["channel"]},
    }},
    {"type": "function", "function": {
        "name": "slack_context_reply",
        "description": "Read recent messages from a channel and post a contextually appropriate reply",
        "parameters": {"type": "object", "properties": {
            "channel": {"type": "string"},
            "intent": {"type": "string", "description": "What to say / intent of the reply"},
        }, "required": ["channel", "intent"]},
    }},
    {"type": "function", "function": {
        "name": "slack_summarize",
        "description": "Summarize recent activity in a Slack channel (does NOT post)",
        "parameters": {"type": "object", "properties": {
            "channel": {"type": "string"},
        }, "required": ["channel"]},
    }},
]


def _client(token: dict):
    from slack_sdk import WebClient
    return WebClient(token=token["access_token"])


def _resolve_channel(client, channel: str) -> str:
    """Accept #channel-name, channel-name, or channel ID."""
    name = channel.lstrip("#").lstrip("@")
    try:
        res = client.conversations_list(types="public_channel,private_channel,im,mpim", limit=200)
        for ch in res.get("channels", []):
            if ch.get("name") == name or ch.get("id") == channel:
                return ch["id"]
    except Exception:
        pass
    return channel  # fall back to raw value (might already be an ID)


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        client = _client(token)

        if name == "slack_send_message":
            channel_id = _resolve_channel(client, args["channel"])
            client.chat_postMessage(channel=channel_id, text=args["text"])
            return True, f"Message sent to {args['channel']}."

        elif name == "slack_search":
            res = client.search_messages(query=args["query"], count=5)
            matches = res.get("messages", {}).get("matches", [])
            if not matches:
                return True, "No messages found."
            lines = [f"[#{m.get('channel',{}).get('name','')}] {m.get('username','')}: {m.get('text','')}" for m in matches]
            return True, "\n".join(lines)

        elif name == "slack_list_channels":
            res = client.conversations_list(types="public_channel,private_channel", exclude_archived=True, limit=100)
            channels = res.get("channels", [])
            if not channels:
                return True, "No channels found."
            return True, "\n".join(f"#{c['name']} (ID:{c['id']})" for c in channels)

        elif name == "slack_read_channel":
            channel_id = _resolve_channel(client, args["channel"])
            res = client.conversations_history(channel=channel_id, limit=args.get("limit", 10))
            msgs = res.get("messages", [])
            if not msgs:
                return True, "No messages."
            lines = []
            for m in reversed(msgs):
                user = m.get("username") or m.get("user", "unknown")
                lines.append(f"{user}: {m.get('text', '')}")
            return True, "\n".join(lines)

        elif name == "slack_context_reply":
            channel_id = _resolve_channel(client, args["channel"])
            res = client.conversations_history(channel=channel_id, limit=10)
            msgs = res.get("messages", [])
            context = "\n".join(
                f"{m.get('username') or m.get('user','?')}: {m.get('text','')}"
                for m in reversed(msgs)
            )
            # Post the intent as a plain message (agent already composed it)
            client.chat_postMessage(channel=channel_id, text=args["intent"])
            return True, f"Reply posted to {args['channel']}."

        elif name == "slack_summarize":
            channel_id = _resolve_channel(client, args["channel"])
            res = client.conversations_history(channel=channel_id, limit=20)
            msgs = res.get("messages", [])
            if not msgs:
                return True, "No recent messages to summarize."
            lines = [
                f"{m.get('username') or m.get('user','?')}: {m.get('text','')}"
                for m in reversed(msgs)
            ]
            return True, "Recent messages:\n" + "\n".join(lines)

        return False, f"Unknown tool: {name}"

    except Exception as e:
        log.error(f"[slack/{name}] {e}")
        return False, str(e)
