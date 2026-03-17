import AppKit

/// A borderless, non-activating floating panel that stays above regular windows.
/// The SwiftUI content view is responsible for all visual styling.
final class FloatingPanel: NSPanel {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: .nonactivatingPanel,
            backing: backingStoreType,
            defer: flag
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false          // SwiftUI .shadow() handles this
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }

    // Do NOT steal key window status — overlay apps (Alfred, Raycast, Spotlight)
    // are also NSPanels and will lose focus if this panel claims key status.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
