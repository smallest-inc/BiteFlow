"""
Agent — GPT-4o multi-turn agent loop.
Ported from agent.rs with the full system prompt preserved.
"""

from __future__ import annotations

import asyncio
import json
import logging
import subprocess
from datetime import datetime
from typing import Callable, Any

from openai import AsyncOpenAI

import config
import history
import dictation as dictation_module

log = logging.getLogger("agent")
_broadcaster: Callable | None = None
_target_bundle_id: str | None = None


def set_event_broadcaster(fn: Callable):
    global _broadcaster
    _broadcaster = fn


def set_target_app(bundle_id: str | None):
    global _target_bundle_id
    _target_bundle_id = bundle_id


async def _emit(event: str, payload: Any):
    if _broadcaster:
        await _broadcaster(event, payload)


# ── System prompt (ported 1:1 from agent.rs) ──

SYSTEM_PROMPT = """You are MiniFlow, a voice-powered desktop agent for macOS. The user speaks and you decide what to do.

MULTILINGUAL SUPPORT:
The user may speak in English, Hindi, or Spanish. You MUST understand commands in ALL three languages and map them to the correct tool calls. The tool parameters (like URLs, app names, queries) should remain in whatever language the user spoke them, except for macOS application names which should always be their actual English names (e.g. "Google Chrome", "Safari", "Finder").

Examples of equivalent commands across languages:
- EN: "Open YouTube" / HI: "YouTube खोलो" / ES: "Abre YouTube" → open_browser_tab
- EN: "Search for restaurants nearby" / HI: "आस-पास के रेस्टोरेंट खोजो" / ES: "Busca restaurantes cercanos" → search_google
- EN: "Send a message on Slack to #general saying hello" / HI: "Slack पर #general में hello भेजो" / ES: "Envía un mensaje en Slack a #general diciendo hola" → slack_send_message
- EN: "Open Finder" / HI: "Finder खोलो" / ES: "Abre Finder" → open_application
- EN: "Quit Safari" / HI: "Safari बंद करो" / ES: "Cierra Safari" → quit_application
- EN: "Copy this to clipboard" / HI: "यह क्लिपबोर्ड में कॉपी करो" / ES: "Copia esto al portapapeles" → clipboard_write
- EN: "Reply in #general agreeing with the plan" / HI: "#general में plan से agree करते हुए reply करो" / ES: "Responde en #general estando de acuerdo con el plan" → slack_context_reply
- EN: "Create a file called notes.txt" / HI: "notes.txt नाम की फाइल बनाओ" / ES: "Crea un archivo llamado notes.txt" → create_file

You have the following LOCAL capabilities (always available):
1. open_browser_tab - Open a URL in Google Chrome
2. search_google - Search Google for a query (opens in Chrome)
3. open_application - Launch a macOS application by name
4. quit_application - Quit a running macOS application
5. clipboard_write - Write text to the clipboard
6. clipboard_read - Read current clipboard contents
7. open_finder - Open a Finder window at a path
8. create_file - Create a new file at a path with optional content
9. move_file - Move/rename a file from one path to another

Only use connector tools that are included in the available tools list for this request.

IMPORTANT DECISION RULE:
- If the user's speech is clearly a COMMAND (in English, Hindi, or Spanish) that matches one of your available tool functions, call the appropriate tool function(s). ALWAYS prefer using a tool over treating text as dictation.
- Hindi command patterns to recognize: "खोलो" (open), "बंद करो" (quit/close), "भेजो" (send), "खोजो/ढूंढो" (search), "बनाओ" (create), "कॉपी करो" (copy), "पढ़ो" (read), "reply करो" (reply), "मूव करो" (move), "ड्राफ्ट" (draft), "मेल/ईमेल" (mail/email).
- Spanish command patterns to recognize: "abre/abrir" (open), "cierra/cerrar" (quit/close), "envía/enviar" (send), "busca/buscar" (search), "crea/crear" (create), "copia/copiar" (copy), "lee/leer" (read), "responde/responder" (reply), "mueve/mover" (move), "borrador" (draft), "correo" (email).

TEXT FORMATTING (when no tool calls are made):
1. EMAIL FORMATTING (only when gmail tools NOT available): format as structured email with greeting, body, sign-off.
2. STRUCTURED DICTATION: detect "bullet points", "numbered list", etc. → return formatted output only.
3. PLAIN DICTATION: respond with ONLY the word "DICTATION".

FILE TAGGING (when [FILE CONTEXT: ...] blocks are present):
- Use the actual file content for fixes, explanations, refactoring.
- Output the FULL modified file when making changes.
- Never say "I need to see the file" — it's already injected.
- Never return "DICTATION" when a code operation is requested with file context."""


# ── Tool definitions ──

LOCAL_TOOLS = [
    {"type": "function", "function": {"name": "open_browser_tab", "description": "Open a URL in Google Chrome", "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}}},
    {"type": "function", "function": {"name": "search_google", "description": "Search Google", "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}}},
    {"type": "function", "function": {"name": "open_application", "description": "Launch a macOS application", "parameters": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}},
    {"type": "function", "function": {"name": "quit_application", "description": "Quit a macOS application", "parameters": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}},
    {"type": "function", "function": {"name": "clipboard_write", "description": "Write text to clipboard", "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}},
    {"type": "function", "function": {"name": "clipboard_read", "description": "Read clipboard contents", "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {"name": "open_finder", "description": "Open Finder at a path", "parameters": {"type": "object", "properties": {"path": {"type": "string", "default": "~"}}, "required": []}}},
    {"type": "function", "function": {"name": "create_file", "description": "Create a file", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string", "default": ""}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "move_file", "description": "Move or rename a file", "parameters": {"type": "object", "properties": {"from": {"type": "string"}, "to": {"type": "string"}}, "required": ["from", "to"]}}},
]


# ── App focus helper ──

async def _activate_target_app():
    """Re-activate the app that was frontmost when Fn was pressed.
    Runs blocking calls in a thread so we don't freeze the asyncio event loop.
    """
    if not _target_bundle_id:
        log.info("_activate_target_app: no target bundle ID stored, skipping")
        return
    log.info(f"_activate_target_app: activating {_target_bundle_id}")
    try:
        result = await asyncio.to_thread(
            subprocess.run,
            ["osascript", "-e", f'tell application id "{_target_bundle_id}" to activate'],
            timeout=2, capture_output=True
        )
        if result.returncode != 0:
            log.warning(f"_activate_target_app: osascript exited {result.returncode}: {result.stderr.decode().strip()}")
        # Wait for focus to settle — 300ms is enough for most apps including Electron/browsers
        await asyncio.sleep(0.30)
        log.info("_activate_target_app: focus settled, ready to type")
    except Exception as e:
        log.warning(f"_activate_target_app: {e}")


# ── Local action execution ──

def _run(cmd: list[str]) -> str:
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return result.stdout.strip() or result.stderr.strip() or "ok"
    except Exception as e:
        return str(e)


def _execute_local(name: str, args: dict) -> tuple[bool, str]:
    import pyperclip
    try:
        if name == "open_browser_tab":
            _run(["open", "-a", "Google Chrome", args["url"]])
            return True, f"Opened {args['url']}"
        elif name == "search_google":
            import urllib.parse
            url = f"https://www.google.com/search?q={urllib.parse.quote(args['query'])}"
            _run(["open", "-a", "Google Chrome", url])
            return True, f"Searched for: {args['query']}"
        elif name == "open_application":
            _run(["open", "-a", args["name"]])
            return True, f"Opened {args['name']}"
        elif name == "quit_application":
            _run(["osascript", "-e", f'quit app "{args["name"]}"'])
            return True, f"Quit {args['name']}"
        elif name == "clipboard_write":
            pyperclip.copy(args["text"])
            return True, "Copied to clipboard"
        elif name == "clipboard_read":
            return True, pyperclip.paste()
        elif name == "open_finder":
            path = args.get("path", "~")
            _run(["open", path])
            return True, f"Opened Finder at {path}"
        elif name == "create_file":
            import os
            path = os.path.expanduser(args["path"])
            with open(path, "w") as f:
                f.write(args.get("content", ""))
            return True, f"Created {path}"
        elif name == "move_file":
            import os, shutil
            shutil.move(os.path.expanduser(args["from"]), os.path.expanduser(args["to"]))
            return True, f"Moved {args['from']} → {args['to']}"
        return False, f"__unknown__:{name}"
    except Exception as e:
        return False, str(e)


# ── File tagging ──

CODE_EXTS = {
    "ts", "tsx", "js", "jsx", "rs", "py", "go", "rb", "java", "cpp", "c",
    "h", "cs", "swift", "kt", "vue", "svelte", "html", "css", "scss",
    "json", "yaml", "yml", "toml", "md", "sh", "bash", "txt", "sql",
}
SKIP_DIRS = {"/node_modules/", "/.git/", "/dist/", "/build/", "/.cache/",
             "/target/", "/.Trash/", "/Library/", "/.venv/"}


def _extract_filenames(text: str) -> list[str]:
    found = []
    for word in text.split():
        clean = word.strip(",.\"'()")
        if "." in clean:
            ext = clean.rsplit(".", 1)[-1].lower()
            if ext in CODE_EXTS and clean not in found:
                found.append(clean)
    return found


def _find_and_read(filename: str) -> tuple[str, str] | None:
    import os
    home = os.path.expanduser("~")
    result = subprocess.run(
        ["mdfind", "-name", filename, "-onlyin", home],
        capture_output=True, text=True, timeout=5
    )
    candidates = [
        p for p in result.stdout.splitlines()
        if not any(skip in p for skip in SKIP_DIRS)
    ]
    if not candidates:
        return None
    best = next(
        (p for p in candidates if any(d in p for d in ("/src/", "/lib/", "/app/"))),
        candidates[0]
    )
    try:
        content = open(best).read()
        if len(content) > 8000:
            content = content[:8000] + "…[truncated]"
        return best, content
    except Exception:
        return None


def _inject_file_context(text: str) -> str:
    filenames = _extract_filenames(text)
    blocks = []
    for fname in filenames:
        result = _find_and_read(fname)
        if result:
            path, content = result
            blocks.append(f"[FILE CONTEXT: {fname} | {path}]\n```\n{content}\n```\n[END FILE CONTEXT]")
            log.info(f"Injected file: {fname} ({path})")
    if blocks:
        prefix = "\n\n".join(blocks)
        text = f"{prefix}\n\n{text}\n\n[SYSTEM: File(s) injected above. Use their actual content to perform the requested operation. Output modified code in full.]"
    return text


# ── Main agent loop ──

async def execute_command(text: str) -> list[dict]:
    await _emit("agent-status", "processing")

    try:
        openai_key = config.get_openai_key()
    except ValueError:
        # No OpenAI key — delegate dictation typing to Swift app process.
        log.info(f"No OpenAI key set, emitting dictation action: '{text[:60]}'")
        result = [{"action": "dictation", "success": True, "message": text}]
        await _emit("action-result", {"action": "dictation", "success": True, "message": text})
        history.append_entry(transcript=text, entry_type="dictation", actions=result, success=True)
        await _emit("agent-status", "idle")
        return result

    client = AsyncOpenAI(api_key=openai_key)
    user_name = config.get_user_name()
    today = datetime.now().strftime("%A, %B %d, %Y")

    user_msg = _inject_file_context(text)
    if user_name:
        user_msg = f"[User name: {user_name}]\n[Today: {today}]\n{user_msg}"
    else:
        user_msg = f"[Today: {today}]\n{user_msg}"

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_msg},
    ]

    # Build tool list: local tools only
    tools = list(LOCAL_TOOLS)

    action_results = []
    max_turns = 8

    for _ in range(max_turns):
        response = await client.chat.completions.create(
            model="gpt-4o",
            messages=messages,
            tools=tools,
            tool_choice="auto",
        )
        msg = response.choices[0].message

        if not msg.tool_calls:
            # No tool call -> emit dictation action; Swift process performs typing.
            # We NEVER type GPT's text response, only original transcript.
            log.info(f"Emitting dictation action: '{text[:60]}'")
            await _emit("action-result", {"action": "dictation", "success": True, "message": text})
            action_results.append({"action": "dictation", "success": True, "message": text})
            break

        messages.append({"role": "assistant", "tool_calls": [
            {"id": tc.id, "type": "function", "function": {"name": tc.function.name, "arguments": tc.function.arguments}}
            for tc in msg.tool_calls
        ]})

        for tc in msg.tool_calls:
            fn_name = tc.function.name
            try:
                args = json.loads(tc.function.arguments)
            except Exception:
                args = {}

            # Try local tools only
            success, result_msg = _execute_local(fn_name, args)

            action_results.append({"action": fn_name, "success": success, "message": result_msg})
            await _emit("action-result", {"action": fn_name, "success": success, "message": result_msg})

            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result_msg,
            })

    history.append_entry(
        transcript=text,
        entry_type="command" if any(r["action"] != "dictation" for r in action_results) else "dictation",
        actions=action_results,
        success=all(r["success"] for r in action_results),
    )

    await _emit("agent-status", "idle")
    return action_results
