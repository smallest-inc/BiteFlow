"""Linear connector — GraphQL API with OAuth2 token."""

from __future__ import annotations

import logging

import httpx

log = logging.getLogger("connectors.linear")

LINEAR_API = "https://api.linear.app/graphql"

TOOLS = [
    {"type": "function", "function": {
        "name": "linear_create_issue",
        "description": "Create a Linear issue",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"},
            "description": {"type": "string"},
            "team_name": {"type": "string", "description": "Team name or key (optional — uses first team if omitted)"},
        }, "required": ["title"]},
    }},
    {"type": "function", "function": {
        "name": "linear_list_issues",
        "description": "List recent Linear issues",
        "parameters": {"type": "object", "properties": {
            "team_name": {"type": "string", "description": "Filter by team name (optional)"},
            "limit": {"type": "integer", "default": 10},
        }, "required": []},
    }},
    {"type": "function", "function": {
        "name": "linear_update_status",
        "description": "Update the status/state of a Linear issue",
        "parameters": {"type": "object", "properties": {
            "issue_id": {"type": "string", "description": "Linear issue ID"},
            "status": {"type": "string", "description": "Target state name (e.g. In Progress, Done)"},
        }, "required": ["issue_id", "status"]},
    }},
]


def _gql(token: dict, query: str, variables: dict | None = None) -> dict:
    res = httpx.post(
        LINEAR_API,
        headers={"Authorization": token["access_token"], "Content-Type": "application/json"},
        json={"query": query, "variables": variables or {}},
        timeout=15,
    )
    res.raise_for_status()
    data = res.json()
    if "errors" in data:
        raise ValueError(data["errors"][0].get("message", "GraphQL error"))
    return data.get("data", {})


def _get_teams(token: dict) -> list[dict]:
    data = _gql(token, "{ teams { nodes { id name key } } }")
    return data.get("teams", {}).get("nodes", [])


def _find_team_id(token: dict, team_name: str | None) -> str | None:
    teams = _get_teams(token)
    if not teams:
        return None
    if not team_name:
        return teams[0]["id"]
    name_lower = team_name.lower()
    for t in teams:
        if t["name"].lower() == name_lower or t["key"].lower() == name_lower:
            return t["id"]
    return teams[0]["id"]


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        if name == "linear_create_issue":
            team_id = _find_team_id(token, args.get("team_name"))
            if not team_id:
                return False, "No Linear teams found."
            data = _gql(token,
                """mutation CreateIssue($title: String!, $description: String, $teamId: String!) {
                    issueCreate(input: {title: $title, description: $description, teamId: $teamId}) {
                        success issue { id identifier url }
                    }
                }""",
                {"title": args["title"], "description": args.get("description", ""), "teamId": team_id},
            )
            issue = data.get("issueCreate", {}).get("issue", {})
            return True, f"Issue created: {issue.get('identifier')}  {issue.get('url', '')}"

        elif name == "linear_list_issues":
            team_id = _find_team_id(token, args.get("team_name"))
            filter_arg = f'(filter: {{team: {{id: {{eq: "{team_id}"}}}}}})' if team_id else ""
            data = _gql(token,
                f"""{{ issues{filter_arg} {{
                    nodes {{ id identifier title state {{ name }} url }}
                }} }}""",
            )
            issues = data.get("issues", {}).get("nodes", [])[:args.get("limit", 10)]
            if not issues:
                return True, "No issues found."
            lines = [f"{i['identifier']}: {i['title']}  [{i['state']['name']}]  {i['url']}" for i in issues]
            return True, "\n".join(lines)

        elif name == "linear_update_status":
            # Find the workflow state ID matching the name
            data = _gql(token, "{ workflowStates { nodes { id name } } }")
            states = data.get("workflowStates", {}).get("nodes", [])
            target = args["status"].lower()
            state_id = None
            for s in states:
                if s["name"].lower() == target or target in s["name"].lower():
                    state_id = s["id"]
                    break
            if not state_id:
                available = [s["name"] for s in states]
                return False, f"State '{args['status']}' not found. Available: {', '.join(available)}"
            data = _gql(token,
                """mutation UpdateIssue($id: String!, $stateId: String!) {
                    issueUpdate(id: $id, input: {stateId: $stateId}) {
                        success issue { identifier state { name } }
                    }
                }""",
                {"id": args["issue_id"], "stateId": state_id},
            )
            issue = data.get("issueUpdate", {}).get("issue", {})
            return True, f"{issue.get('identifier')} updated to '{issue.get('state', {}).get('name')}'."

        return False, f"Unknown tool: {name}"

    except Exception as e:
        log.error(f"[linear/{name}] {e}")
        return False, str(e)
