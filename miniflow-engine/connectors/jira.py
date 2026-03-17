"""Jira connector — Atlassian Cloud via REST API with OAuth2 token."""

from __future__ import annotations

import logging

import httpx

log = logging.getLogger("connectors.jira")

ATLASSIAN_API = "https://api.atlassian.com"

TOOLS = [
    {"type": "function", "function": {
        "name": "jira_create_issue",
        "description": "Create a Jira issue",
        "parameters": {"type": "object", "properties": {
            "project": {"type": "string", "description": "Jira project key (e.g. ENG)"},
            "summary": {"type": "string"},
            "description": {"type": "string"},
            "issue_type": {"type": "string", "default": "Task"},
        }, "required": ["project", "summary"]},
    }},
    {"type": "function", "function": {
        "name": "jira_search",
        "description": "Search Jira issues using JQL or plain text",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string", "description": "JQL query or keywords"},
            "limit": {"type": "integer", "default": 10},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "jira_update_status",
        "description": "Transition a Jira issue to a new status",
        "parameters": {"type": "object", "properties": {
            "issue_key": {"type": "string", "description": "e.g. ENG-123"},
            "status": {"type": "string", "description": "Target status name (e.g. In Progress, Done)"},
        }, "required": ["issue_key", "status"]},
    }},
]


def _headers(token: dict) -> dict:
    return {
        "Authorization": f"Bearer {token['access_token']}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def _cloud_id(token: dict) -> str:
    """Fetch the first accessible Jira cloud site ID."""
    res = httpx.get(
        f"{ATLASSIAN_API}/oauth/token/accessible-resources",
        headers=_headers(token),
        timeout=10,
    )
    res.raise_for_status()
    resources = res.json()
    if not resources:
        raise ValueError("No accessible Jira sites found. Make sure Jira is authorised.")
    return resources[0]["id"]


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        cloud_id = _cloud_id(token)
        base = f"{ATLASSIAN_API}/ex/jira/{cloud_id}/rest/api/3"
        headers = _headers(token)

        if name == "jira_create_issue":
            payload = {
                "fields": {
                    "project": {"key": args["project"]},
                    "summary": args["summary"],
                    "description": {
                        "type": "doc", "version": 1,
                        "content": [{"type": "paragraph", "content": [
                            {"type": "text", "text": args.get("description", "")}
                        ]}],
                    },
                    "issuetype": {"name": args.get("issue_type", "Task")},
                }
            }
            res = httpx.post(f"{base}/issue", headers=headers, json=payload, timeout=10)
            res.raise_for_status()
            data = res.json()
            return True, f"Issue created: {data.get('key')}  https://your-domain.atlassian.net/browse/{data.get('key')}"

        elif name == "jira_search":
            jql = args["query"] if "=" in args["query"] or "ORDER" in args["query"].upper() else f'text ~ "{args["query"]}"'
            res = httpx.post(
                f"{base}/search",
                headers=headers,
                json={"jql": jql, "maxResults": args.get("limit", 10), "fields": ["summary", "status", "assignee"]},
                timeout=10,
            )
            res.raise_for_status()
            issues = res.json().get("issues", [])
            if not issues:
                return True, "No issues found."
            lines = [
                f"{i['key']}: {i['fields']['summary']}  [{i['fields']['status']['name']}]"
                for i in issues
            ]
            return True, "\n".join(lines)

        elif name == "jira_update_status":
            # Get available transitions
            res = httpx.get(f"{base}/issue/{args['issue_key']}/transitions", headers=headers, timeout=10)
            res.raise_for_status()
            transitions = res.json().get("transitions", [])
            target = args["status"].lower()
            transition_id = None
            for t in transitions:
                if t["name"].lower() == target or target in t["name"].lower():
                    transition_id = t["id"]
                    break
            if not transition_id:
                available = [t["name"] for t in transitions]
                return False, f"Status '{args['status']}' not found. Available: {', '.join(available)}"
            res = httpx.post(
                f"{base}/issue/{args['issue_key']}/transitions",
                headers=headers,
                json={"transition": {"id": transition_id}},
                timeout=10,
            )
            res.raise_for_status()
            return True, f"{args['issue_key']} moved to '{args['status']}'."

        return False, f"Unknown tool: {name}"

    except httpx.HTTPStatusError as e:
        log.error(f"[jira/{name}] HTTP {e.response.status_code}: {e.response.text}")
        return False, f"Jira API error {e.response.status_code}: {e.response.text[:200]}"
    except Exception as e:
        log.error(f"[jira/{name}] {e}")
        return False, str(e)
