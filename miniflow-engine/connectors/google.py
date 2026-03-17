"""Google connector — Gmail, Google Calendar, Google Drive."""

from __future__ import annotations

import base64
import logging
from datetime import datetime, timedelta, timezone
from email.mime.text import MIMEText

log = logging.getLogger("connectors.google")

# ── Tool definitions ──

GMAIL_TOOLS = [
    {"type": "function", "function": {
        "name": "gmail_search",
        "description": "Search Gmail emails",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "limit": {"type": "integer", "default": 5},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "gmail_read",
        "description": "Read a Gmail email by message ID",
        "parameters": {"type": "object", "properties": {
            "id": {"type": "string"},
        }, "required": ["id"]},
    }},
    {"type": "function", "function": {
        "name": "gmail_send",
        "description": "Send an email via Gmail",
        "parameters": {"type": "object", "properties": {
            "to": {"type": "string"},
            "subject": {"type": "string"},
            "body": {"type": "string"},
        }, "required": ["to", "subject", "body"]},
    }},
    {"type": "function", "function": {
        "name": "gmail_reply",
        "description": "Reply to an existing email thread",
        "parameters": {"type": "object", "properties": {
            "threadId": {"type": "string"},
            "body": {"type": "string"},
        }, "required": ["threadId", "body"]},
    }},
    {"type": "function", "function": {
        "name": "gmail_draft",
        "description": "Create a Gmail draft",
        "parameters": {"type": "object", "properties": {
            "to": {"type": "string"},
            "subject": {"type": "string"},
            "body": {"type": "string"},
        }, "required": ["to", "subject", "body"]},
    }},
]

CALENDAR_TOOLS = [
    {"type": "function", "function": {
        "name": "calendar_list_events",
        "description": "List upcoming calendar events",
        "parameters": {"type": "object", "properties": {
            "days_ahead": {"type": "integer", "default": 7},
        }, "required": []},
    }},
    {"type": "function", "function": {
        "name": "calendar_create_event",
        "description": "Create a new calendar event",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"},
            "start": {"type": "string", "description": "ISO 8601 datetime"},
            "end": {"type": "string", "description": "ISO 8601 datetime"},
            "attendees": {"type": "array", "items": {"type": "string"}, "default": []},
        }, "required": ["title", "start", "end"]},
    }},
    {"type": "function", "function": {
        "name": "calendar_check_availability",
        "description": "Check free/busy on a given date",
        "parameters": {"type": "object", "properties": {
            "date": {"type": "string", "description": "ISO 8601 date or datetime"},
            "duration_hours": {"type": "number", "default": 1},
        }, "required": ["date"]},
    }},
]

DRIVE_TOOLS = [
    {"type": "function", "function": {
        "name": "drive_search",
        "description": "Search files in Google Drive",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "limit": {"type": "integer", "default": 5},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "drive_read",
        "description": "Export a Google Drive file as plain text",
        "parameters": {"type": "object", "properties": {
            "fileId": {"type": "string"},
        }, "required": ["fileId"]},
    }},
    {"type": "function", "function": {
        "name": "drive_list",
        "description": "List files in Google Drive (optionally in a folder)",
        "parameters": {"type": "object", "properties": {
            "folderId": {"type": "string"},
        }, "required": []},
    }},
]

TOOLS = GMAIL_TOOLS + CALENDAR_TOOLS + DRIVE_TOOLS

# ── Helpers ──

def _creds(token: dict):
    from google.oauth2.credentials import Credentials
    return Credentials(
        token=token["access_token"],
        refresh_token=token.get("refresh_token") or None,
        token_uri="https://oauth2.googleapis.com/token",
    )


def _gmail_svc(token: dict):
    from googleapiclient.discovery import build
    return build("gmail", "v1", credentials=_creds(token), cache_discovery=False)


def _cal_svc(token: dict):
    from googleapiclient.discovery import build
    return build("calendar", "v3", credentials=_creds(token), cache_discovery=False)


def _drive_svc(token: dict):
    from googleapiclient.discovery import build
    return build("drive", "v3", credentials=_creds(token), cache_discovery=False)


def _make_mime(to: str, subject: str, body: str, thread_id: str | None = None) -> dict:
    msg = MIMEText(body)
    msg["To"] = to
    msg["Subject"] = subject
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    result: dict = {"raw": raw}
    if thread_id:
        result["threadId"] = thread_id
    return result


def _decode_body(payload: dict) -> str:
    """Extract plain-text body from a Gmail message payload."""
    data = payload.get("body", {}).get("data")
    if data:
        return base64.urlsafe_b64decode(data).decode("utf-8", errors="replace")
    for part in payload.get("parts", []):
        if part.get("mimeType") == "text/plain":
            d = part.get("body", {}).get("data")
            if d:
                return base64.urlsafe_b64decode(d).decode("utf-8", errors="replace")
    return ""

# ── Execution ──

def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        # ── Gmail ──
        if name == "gmail_search":
            svc = _gmail_svc(token)
            res = svc.users().messages().list(
                userId="me", q=args["query"], maxResults=args.get("limit", 5)
            ).execute()
            msgs = res.get("messages", [])
            if not msgs:
                return True, "No emails found."
            lines = []
            for m in msgs:
                hdr = svc.users().messages().get(
                    userId="me", id=m["id"], format="metadata",
                    metadataHeaders=["From", "Subject"],
                ).execute()
                headers = {h["name"]: h["value"] for h in hdr.get("payload", {}).get("headers", [])}
                lines.append(f"ID:{m['id']}  From:{headers.get('From','')}  Subject:{headers.get('Subject','')}")
            return True, "\n".join(lines)

        elif name == "gmail_read":
            svc = _gmail_svc(token)
            msg = svc.users().messages().get(userId="me", id=args["id"], format="full").execute()
            headers = {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}
            body = _decode_body(msg.get("payload", {}))
            thread_id = msg.get("threadId", "")
            return True, (
                f"From: {headers.get('From','')}\n"
                f"Subject: {headers.get('Subject','')}\n"
                f"ThreadID: {thread_id}\n\n"
                f"{body[:2500]}"
            )

        elif name == "gmail_send":
            svc = _gmail_svc(token)
            svc.users().messages().send(
                userId="me", body=_make_mime(args["to"], args["subject"], args["body"])
            ).execute()
            return True, f"Email sent to {args['to']}."

        elif name == "gmail_reply":
            svc = _gmail_svc(token)
            thread = svc.users().threads().get(userId="me", id=args["threadId"]).execute()
            first_msg = thread["messages"][0]
            headers = {h["name"]: h["value"] for h in first_msg.get("payload", {}).get("headers", [])}
            to = headers.get("Reply-To") or headers.get("From", "")
            subject = headers.get("Subject", "")
            if not subject.lower().startswith("re:"):
                subject = f"Re: {subject}"
            svc.users().messages().send(
                userId="me",
                body=_make_mime(to, subject, args["body"], args["threadId"]),
            ).execute()
            return True, f"Reply sent to thread {args['threadId']}."

        elif name == "gmail_draft":
            svc = _gmail_svc(token)
            svc.users().drafts().create(
                userId="me",
                body={"message": _make_mime(args["to"], args["subject"], args["body"])},
            ).execute()
            return True, f"Draft created for {args['to']}."

        # ── Calendar ──
        elif name == "calendar_list_events":
            svc = _cal_svc(token)
            now = datetime.now(timezone.utc)
            end = now + timedelta(days=args.get("days_ahead", 7))
            res = svc.events().list(
                calendarId="primary",
                timeMin=now.isoformat(),
                timeMax=end.isoformat(),
                singleEvents=True,
                orderBy="startTime",
            ).execute()
            events = res.get("items", [])
            if not events:
                return True, "No upcoming events."
            lines = []
            for e in events:
                start = e["start"].get("dateTime", e["start"].get("date", ""))
                lines.append(f"{start}: {e.get('summary', 'No title')}")
            return True, "\n".join(lines)

        elif name == "calendar_create_event":
            svc = _cal_svc(token)
            body: dict = {
                "summary": args["title"],
                "start": {"dateTime": args["start"], "timeZone": "America/New_York"},
                "end": {"dateTime": args["end"], "timeZone": "America/New_York"},
            }
            if args.get("attendees"):
                body["attendees"] = [{"email": a} for a in args["attendees"]]
            event = svc.events().insert(
                calendarId="primary", body=body, sendUpdates="all"
            ).execute()
            return True, f"Event created: {event.get('htmlLink', event.get('id', ''))}"

        elif name == "calendar_check_availability":
            svc = _cal_svc(token)
            try:
                dt = datetime.fromisoformat(args["date"])
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
            except Exception:
                dt = datetime.now(timezone.utc)
            window_end = dt + timedelta(hours=8)
            res = svc.freebusy().query(body={
                "timeMin": dt.isoformat(),
                "timeMax": window_end.isoformat(),
                "items": [{"id": "primary"}],
            }).execute()
            busy = res.get("calendars", {}).get("primary", {}).get("busy", [])
            if not busy:
                return True, f"Calendar is free on {args['date']}."
            slots = [f"Busy {b['start']} – {b['end']}" for b in busy]
            return True, "\n".join(slots)

        # ── Drive ──
        elif name == "drive_search":
            svc = _drive_svc(token)
            q = f"fullText contains '{args['query']}' and trashed = false"
            res = svc.files().list(
                q=q, pageSize=args.get("limit", 5), fields="files(id,name,mimeType)"
            ).execute()
            files = res.get("files", [])
            if not files:
                return True, "No files found."
            return True, "\n".join(f"ID:{f['id']}  {f['name']}  ({f['mimeType']})" for f in files)

        elif name == "drive_read":
            svc = _drive_svc(token)
            content = svc.files().export(
                fileId=args["fileId"], mimeType="text/plain"
            ).execute()
            text = content.decode("utf-8", errors="replace") if isinstance(content, bytes) else str(content)
            return True, text[:3000]

        elif name == "drive_list":
            svc = _drive_svc(token)
            q = f"'{args['folderId']}' in parents and trashed = false" if args.get("folderId") else "trashed = false"
            res = svc.files().list(q=q, pageSize=20, fields="files(id,name,mimeType)").execute()
            files = res.get("files", [])
            if not files:
                return True, "No files found."
            return True, "\n".join(f"ID:{f['id']}  {f['name']}" for f in files)

        return False, f"Unknown tool: {name}"

    except Exception as e:
        log.error(f"[google/{name}] {e}")
        return False, str(e)
