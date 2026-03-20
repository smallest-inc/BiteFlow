"""
Dictation — keystroke injection into the focused app.
Uses pyobjc Quartz CGEvent for key simulation (same API as the old Rust impl).
"""

from __future__ import annotations

import asyncio
import logging
import subprocess
from typing import Callable, Awaitable

log = logging.getLogger("dictation")
_broadcaster: Callable | None = None
_active = False


def set_event_broadcaster(fn: Callable):
    global _broadcaster
    _broadcaster = fn


async def _emit(event: str, payload):
    if _broadcaster:
        await _broadcaster(event, payload)


try:
    from Quartz import AXIsProcessTrusted as _AXIsProcessTrusted
    def AXIsProcessTrusted() -> bool:
        return _AXIsProcessTrusted()
except Exception:
    def AXIsProcessTrusted() -> bool:
        return False


def check_accessibility() -> bool:
    return AXIsProcessTrusted()


def open_accessibility_settings():
    subprocess.Popen([
        "open",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ])


def get_dictation_status() -> bool:
    return _active


async def start_dictation():
    global _active
    _active = True
    await _emit("dictation-status", {"active": True, "error": None})
    log.info("Dictation started")


async def stop_dictation():
    global _active
    _active = False
    await _emit("dictation-status", {"active": False, "error": None})
    log.info("Dictation stopped")


def type_text(text: str):
    """Inject text via clipboard paste (Cmd+V), then restore the previous clipboard."""
    try:
        import time
        import Quartz
        import AppKit
        if not text:
            return
        log.info(f"type_text: pasting {len(text)} chars")
        pb = AppKit.NSPasteboard.generalPasteboard()

        # Save previous clipboard contents
        prev = pb.stringForType_(AppKit.NSPasteboardTypeString)

        pb.clearContents()
        pb.setString_forType_(text, AppKit.NSPasteboardTypeString)

        src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
        kVK_V = 0x09
        down = Quartz.CGEventCreateKeyboardEvent(src, kVK_V, True)
        up   = Quartz.CGEventCreateKeyboardEvent(src, kVK_V, False)
        Quartz.CGEventSetFlags(down, Quartz.kCGEventFlagMaskCommand)
        Quartz.CGEventSetFlags(up,   Quartz.kCGEventFlagMaskCommand)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)

        # Wait briefly for the paste to land, then restore
        time.sleep(0.1)
        pb.clearContents()
        if prev is not None:
            pb.setString_forType_(prev, AppKit.NSPasteboardTypeString)

        log.info("type_text: done")
    except Exception as e:
        log.error(f"type_text failed: {e}")
