"""
Audio — streams PCM chunks to the Smallest AI Waves WebSocket API in real-time.
Falls back to REST POST if the streaming connection fails.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Callable, Awaitable

import httpx
import websockets

import config

log = logging.getLogger("audio")

_WSS_URL = "wss://api.smallest.ai/waves/v1/pulse/get_text"
_REST_URL = "https://waves-api.smallest.ai/api/v1/pulse/get_text"


async def stream_transcribe(
    chunk_queue: asyncio.Queue,
    on_partial: Callable[[str], Awaitable[None]] | None = None,
) -> str:
    """
    Connect to Smallest AI WSS, forward raw PCM chunks from chunk_queue,
    collect partial transcripts, and return the final transcript.
    Put None into chunk_queue to signal end of audio.
    """
    try:
        key = config.get_smallest_key()
    except ValueError as e:
        raise RuntimeError(str(e)) from e

    headers = {"Authorization": f"Bearer {key}"}
    url = f"{_WSS_URL}?language=en&encoding=linear16&sample_rate=16000"

    final_transcript = ""
    last_text = ""
    segments: list[str] = []  # accumulates each finalized segment
    total_pcm_bytes = 0
    t0 = time.perf_counter()
    finalize_time = 0.0
    final_received_time = 0.0
    finalize_sent = asyncio.Event()

    # ping_interval keeps connection alive during long recordings (up to ~60s+)
    async with websockets.connect(
        url,
        additional_headers=headers,
        ping_interval=10,
        ping_timeout=30,
        close_timeout=10,
    ) as ws:

        async def sender():
            nonlocal total_pcm_bytes, finalize_time
            while True:
                chunk = await chunk_queue.get()
                if chunk is None:  # sentinel — send finalize signal to server
                    await ws.send(json.dumps({"type": "finalize"}))
                    finalize_time = time.perf_counter()
                    finalize_sent.set()
                    return
                total_pcm_bytes += len(chunk)
                await ws.send(chunk)

        async def receiver():
            nonlocal final_transcript, last_text, final_received_time
            try:
                async for raw in ws:
                    log.info(f"WSS response: {str(raw)[:300]}")
                    try:
                        data = json.loads(raw)
                    except Exception:
                        continue
                    text = data.get("transcript") or ""
                    is_final = data.get("is_final", False)
                    is_last = data.get("is_last", False)
                    if is_final and text:
                        # Segment finalized — append to accumulation
                        segments.append(text.strip())
                        last_text = "".join(segments)
                        if on_partial:
                            await on_partial(last_text)
                    elif text and not is_final:
                        # Partial — show accumulated segments + current partial
                        preview = "".join(segments) + ("" if segments else "") + text.strip()
                        if on_partial:
                            await on_partial(preview)
                    if is_last:
                        final_transcript = last_text
                        final_received_time = time.perf_counter()
                        break
                    # Only break on is_final after finalize sent
                    if is_final and finalize_sent.is_set():
                        final_transcript = last_text
                        final_received_time = time.perf_counter()
                        break
            except websockets.exceptions.ConnectionClosed:
                pass  # connection closed — fallback to last_text below

        sender_task = asyncio.create_task(sender())
        receiver_task = asyncio.create_task(receiver())

        # Wait for all chunks sent, then up to 15s for is_last (longer for long recordings)
        await sender_task
        try:
            await asyncio.wait_for(asyncio.shield(receiver_task), timeout=15.0)
        except asyncio.TimeoutError:
            log.warning("WSS receiver timed out waiting for final transcript")
        receiver_task.cancel()
        try:
            await receiver_task
        except asyncio.CancelledError:
            pass
        # Fallback: use accumulated full_transcript if is_last never arrived
        if not final_transcript and last_text:
            final_transcript = last_text

    audio_length_s = total_pcm_bytes / 32000  # 16kHz * 16-bit = 32000 bytes/sec
    finalize_to_final_ms = (final_received_time - finalize_time) * 1000 if final_received_time and finalize_time else 0
    total_ms = (time.perf_counter() - t0) * 1000
    log.info(
        f"[LATENCY] ┌─ WSS STT ─────────────────────────────\n"
        f"          │  Audio length     : {audio_length_s:.2f}s\n"
        f"          │  Finalize → final : {finalize_to_final_ms:.0f}ms\n"
        f"          │  Total session    : {total_ms:.0f}ms\n"
        f"          │  Transcript       : '{final_transcript[:80]}'\n"
        f"          └──────────────────────────────────────────"
    )
    return final_transcript


async def transcribe(wav_bytes: bytes) -> str:
    """Fallback: POST complete WAV to REST endpoint."""
    try:
        key = config.get_smallest_key()
    except ValueError as e:
        raise RuntimeError(str(e)) from e

    headers = {"Authorization": f"Bearer {key}", "Content-Type": "audio/wav"}
    params = {"model": "pulse", "language": "en"}

    t0 = time.perf_counter()
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(_REST_URL, headers=headers, params=params, content=wav_bytes)
        resp.raise_for_status()
        data = resp.json()
    stt_ms = (time.perf_counter() - t0) * 1000

    transcript = data.get("transcription") or data.get("transcript") or ""
    log.info(f"[LATENCY] REST STT: {stt_ms:.0f}ms | transcript: '{transcript}'")
    return transcript
