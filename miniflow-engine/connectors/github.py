"""GitHub connector — uses PyGithub with OAuth token."""

from __future__ import annotations

import logging

log = logging.getLogger("connectors.github")

TOOLS = [
    {"type": "function", "function": {
        "name": "github_create_issue",
        "description": "Create a GitHub issue in a repository",
        "parameters": {"type": "object", "properties": {
            "repo": {"type": "string", "description": "owner/repo format"},
            "title": {"type": "string"},
            "body": {"type": "string"},
        }, "required": ["repo", "title"]},
    }},
    {"type": "function", "function": {
        "name": "github_list_issues",
        "description": "List open issues in a GitHub repository",
        "parameters": {"type": "object", "properties": {
            "repo": {"type": "string", "description": "owner/repo format"},
            "limit": {"type": "integer", "default": 10},
        }, "required": ["repo"]},
    }},
    {"type": "function", "function": {
        "name": "github_create_pr",
        "description": "Create a pull request on GitHub",
        "parameters": {"type": "object", "properties": {
            "repo": {"type": "string", "description": "owner/repo format"},
            "title": {"type": "string"},
            "body": {"type": "string"},
            "head": {"type": "string", "description": "source branch"},
            "base": {"type": "string", "description": "target branch", "default": "main"},
        }, "required": ["repo", "title", "head"]},
    }},
    {"type": "function", "function": {
        "name": "github_search_repos",
        "description": "Search GitHub repositories",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "limit": {"type": "integer", "default": 5},
        }, "required": ["query"]},
    }},
]


def _gh(token: dict):
    from github import Github
    return Github(token["access_token"])


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        gh = _gh(token)

        if name == "github_create_issue":
            repo = gh.get_repo(args["repo"])
            issue = repo.create_issue(
                title=args["title"],
                body=args.get("body", ""),
            )
            return True, f"Issue created: {issue.html_url}"

        elif name == "github_list_issues":
            repo = gh.get_repo(args["repo"])
            issues = list(repo.get_issues(state="open"))[:args.get("limit", 10)]
            if not issues:
                return True, "No open issues."
            lines = [f"#{i.number}: {i.title}  ({i.html_url})" for i in issues]
            return True, "\n".join(lines)

        elif name == "github_create_pr":
            repo = gh.get_repo(args["repo"])
            pr = repo.create_pull(
                title=args["title"],
                body=args.get("body", ""),
                head=args["head"],
                base=args.get("base", "main"),
            )
            return True, f"PR created: {pr.html_url}"

        elif name == "github_search_repos":
            results = gh.search_repositories(query=args["query"])
            repos = list(results)[:args.get("limit", 5)]
            if not repos:
                return True, "No repositories found."
            lines = [f"{r.full_name}  ★{r.stargazers_count}  {r.html_url}" for r in repos]
            return True, "\n".join(lines)

        return False, f"Unknown tool: {name}"

    except Exception as e:
        log.error(f"[github/{name}] {e}")
        return False, str(e)
