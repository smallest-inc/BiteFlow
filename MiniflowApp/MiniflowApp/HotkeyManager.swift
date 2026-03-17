import AppKit

/// Monitors the Fn/Globe key using NSEvent flag monitoring (hold-to-talk).
/// Hold Fn → onPress fires. Release Fn → onRelease fires.
///
/// NOTE: Set System Settings → Keyboard → "Press Fn key to" → "Do Nothing"
/// otherwise the Emoji picker or input switcher will also activate.
@MainActor
final class HotkeyManager {

    static let shared = HotkeyManager()

    var onPress: (() -> Void)?    // Fn key down
    var onRelease: (() -> Void)?  // Fn key up

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnDown = false

    private init() {}

    func register() {
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let isFn = event.modifierFlags.contains(.function)
            if isFn && !self.fnDown {
                self.fnDown = true
                self.onPress?()
            } else if !isFn && self.fnDown {
                self.fnDown = false
                self.onRelease?()
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in handle(event) }
            return event
        }
    }

    func unregister() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor  { NSEvent.removeMonitor(l); localMonitor  = nil }
        fnDown = false
    }
}
