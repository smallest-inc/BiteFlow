"""Spotify connector — Spotify Web API with OAuth2 token."""

from __future__ import annotations

import logging

import httpx

log = logging.getLogger("connectors.spotify")

SPOTIFY_API = "https://api.spotify.com/v1"

TOOLS = [
    {"type": "function", "function": {
        "name": "spotify_now_playing",
        "description": "Get the currently playing Spotify track",
        "parameters": {"type": "object", "properties": {}, "required": []},
    }},
    {"type": "function", "function": {
        "name": "spotify_play",
        "description": "Start or resume Spotify playback, optionally with a track/album/playlist URI",
        "parameters": {"type": "object", "properties": {
            "uri": {"type": "string", "description": "Spotify URI (spotify:track:...) — omit to resume"},
        }, "required": []},
    }},
    {"type": "function", "function": {
        "name": "spotify_pause",
        "description": "Pause Spotify playback",
        "parameters": {"type": "object", "properties": {}, "required": []},
    }},
    {"type": "function", "function": {
        "name": "spotify_skip",
        "description": "Skip to next or previous track",
        "parameters": {"type": "object", "properties": {
            "direction": {"type": "string", "enum": ["next", "previous"], "default": "next"},
        }, "required": []},
    }},
    {"type": "function", "function": {
        "name": "spotify_search",
        "description": "Search for tracks, artists, albums, or playlists on Spotify",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "type": {"type": "string", "enum": ["track", "artist", "album", "playlist"], "default": "track"},
            "limit": {"type": "integer", "default": 5},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "spotify_queue",
        "description": "Add a track to the Spotify queue",
        "parameters": {"type": "object", "properties": {
            "uri": {"type": "string", "description": "Spotify track URI (spotify:track:...)"},
        }, "required": ["uri"]},
    }},
]


def _headers(token: dict) -> dict:
    return {"Authorization": f"Bearer {token['access_token']}"}


def execute(name: str, args: dict, token: dict) -> tuple[bool, str]:
    try:
        headers = _headers(token)

        if name == "spotify_now_playing":
            res = httpx.get(f"{SPOTIFY_API}/me/player/currently-playing", headers=headers, timeout=10)
            if res.status_code == 204:
                return True, "Nothing is currently playing."
            res.raise_for_status()
            data = res.json()
            item = data.get("item")
            if not item:
                return True, "Nothing is currently playing."
            artists = ", ".join(a["name"] for a in item.get("artists", []))
            return True, f"Now playing: {item['name']} by {artists}  ({item.get('album', {}).get('name', '')})"

        elif name == "spotify_play":
            body = {}
            uri = args.get("uri")
            if uri:
                if uri.startswith("spotify:track:"):
                    body = {"uris": [uri]}
                else:
                    body = {"context_uri": uri}
            res = httpx.put(f"{SPOTIFY_API}/me/player/play", headers=headers, json=body, timeout=10)
            if res.status_code in (200, 204):
                return True, "Playback started."
            res.raise_for_status()
            return True, "Playback started."

        elif name == "spotify_pause":
            res = httpx.put(f"{SPOTIFY_API}/me/player/pause", headers=headers, timeout=10)
            if res.status_code in (200, 204):
                return True, "Playback paused."
            res.raise_for_status()
            return True, "Paused."

        elif name == "spotify_skip":
            direction = args.get("direction", "next")
            endpoint = "next" if direction == "next" else "previous"
            res = httpx.post(f"{SPOTIFY_API}/me/player/{endpoint}", headers=headers, timeout=10)
            if res.status_code in (200, 204):
                return True, f"Skipped to {direction} track."
            res.raise_for_status()
            return True, f"Skipped {direction}."

        elif name == "spotify_search":
            search_type = args.get("type", "track")
            res = httpx.get(
                f"{SPOTIFY_API}/search",
                headers=headers,
                params={"q": args["query"], "type": search_type, "limit": args.get("limit", 5)},
                timeout=10,
            )
            res.raise_for_status()
            data = res.json()
            key = f"{search_type}s"
            items = data.get(key, {}).get("items", [])
            if not items:
                return True, f"No {search_type}s found for '{args['query']}'."
            lines = []
            for item in items:
                if search_type == "track":
                    artists = ", ".join(a["name"] for a in item.get("artists", []))
                    lines.append(f"{item['name']} by {artists}  URI:{item['uri']}")
                else:
                    lines.append(f"{item.get('name', '')}  URI:{item.get('uri', '')}")
            return True, "\n".join(lines)

        elif name == "spotify_queue":
            res = httpx.post(
                f"{SPOTIFY_API}/me/player/queue",
                headers=headers,
                params={"uri": args["uri"]},
                timeout=10,
            )
            if res.status_code in (200, 204):
                return True, f"Added to queue: {args['uri']}"
            res.raise_for_status()
            return True, "Added to queue."

        return False, f"Unknown tool: {name}"

    except httpx.HTTPStatusError as e:
        log.error(f"[spotify/{name}] HTTP {e.response.status_code}: {e.response.text}")
        if e.response.status_code == 401:
            return False, "Spotify token expired. Please reconnect Spotify in Settings."
        if e.response.status_code == 403:
            return False, "Spotify Premium required for playback control."
        return False, f"Spotify API error {e.response.status_code}."
    except Exception as e:
        log.error(f"[spotify/{name}] {e}")
        return False, str(e)
