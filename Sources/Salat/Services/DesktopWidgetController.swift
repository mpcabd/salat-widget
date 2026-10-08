import AppKit
import SwiftUI

/// Hosts `WidgetView` in a borderless panel pinned to the desktop (or floating above windows).
@MainActor
final class DesktopWidgetController {
    private unowned let model: AppModel
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var applied: (WidgetSize, WidgetStyle, Bool, Bool)?

    init(model: AppModel) {
        self.model = model
    }

    func sync() {
        let s = model.settings
        guard s.widgetEnabled else {
            panel?.orderOut(nil)
            applied = nil
            return
        }
        let state = (s.widgetSize, s.widgetStyle, s.widgetFloating, model.isArabic)
        if let a = applied, a == state, panel?.isVisible == true { return }
        applied = state

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.level = s.widgetFloating
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        let host = DraggableHostingView(rootView: AnyView(WidgetContainer().environment(model)))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        let size = host.fittingSize
        let origin = savedOrigin(for: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 170),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrigin() }
        }
        return p
    }

    private func savedOrigin(for size: CGSize) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let x = model.settings.widgetOriginX, let y = model.settings.widgetOriginY {
            let p = CGPoint(x: x, y: y)
            // Make sure it's still on some screen (monitors change).
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(p) }) {
                return p
            }
        }
        return CGPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24)
    }

    private func saveOrigin() {
        guard let o = panel?.frame.origin else { return }
        if model.settings.widgetOriginX != o.x || model.settings.widgetOriginY != o.y {
            model.settings.widgetOriginX = o.x
            model.settings.widgetOriginY = o.y
        }
    }
}

/// Lets the user drag the borderless widget from anywhere on its surface.
private final class DraggableHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }

    // SwiftUI swallows mouseDown, so background dragging never kicks in on its own.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            super.mouseDown(with: event) // control-click opens the context menu
        } else {
            window?.performDrag(with: event)
        }
    }
}

private struct WidgetContainer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let L = model.L
        WidgetView(size: model.settings.widgetSize, style: model.settings.widgetStyle)
            .padding(10) // room for the shadow
            .contextMenu {
                Picker(L.t("widget.size"), selection: Binding(
                    get: { model.settings.widgetSize }, set: { model.settings.widgetSize = $0 })) {
                    ForEach(WidgetSize.allCases) { Text(L.t("widget.size.\($0.rawValue)")).tag($0) }
                }
                Picker(L.t("widget.style"), selection: Binding(
                    get: { model.settings.widgetStyle }, set: { model.settings.widgetStyle = $0 })) {
                    ForEach(WidgetStyle.allCases) { Text(L.t("widget.style.\($0.rawValue)")).tag($0) }
                }
                Toggle(L.t("widget.floating"), isOn: Binding(
                    get: { model.settings.widgetFloating }, set: { model.settings.widgetFloating = $0 }))
                Divider()
                Button(L.t("footer.settings")) { model.open("settings") }
                Button(L.t("widget.hide")) { model.settings.widgetEnabled = false }
            }
    }
}
