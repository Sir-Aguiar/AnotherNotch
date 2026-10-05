import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        // O canvas cobre a barra de menus. O rastreamento libera o clique fora da pílula.
        ignoresMouseEvents = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var isReinjectingEvent = false

    override func sendEvent(_ event: NSEvent) {
        if isReinjectingEvent {
            return
        }

        if let hosting = contentView as? NotchHostingView {
            hosting.syncPointer()
        }

        let isClick = event.type == .leftMouseDown
            || event.type == .rightMouseDown
            || event.type == .otherMouseDown
        if ignoresMouseEvents {
            guard isClick, let replay = event.cgEvent?.copy() else { return }
            isReinjectingEvent = true
            DispatchQueue.main.async { [weak self] in
                replay.post(tap: .cgSessionEventTap)
                self?.isReinjectingEvent = false
            }
            return
        }

        super.sendEvent(event)
    }
}

final class NotchHostingView: NSHostingView<ContentView> {
    var onHoverChange: ((Bool) -> Void)?
    private(set) var pointerInsidePill = false

    private var trackingArea: NSTrackingArea?
    private var pillRect: CGRect = .zero
    private var pillSize: CGSize = .zero
    private var bottomRadius: CGFloat = NotchState.collapsedCornerRadius
    /// O cursor não entra no recorte físico; a zona de hover desce um pouco abaixo da pílula.
    private let hoverOverflow: CGFloat = 22
    private var pendingSize: CGSize?
    private var sizeApplyScheduled = false
    private var isRefreshingTracking = false

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard pillContains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    func updatePillSize(_ size: CGSize) {
        pendingSize = size
        guard !sizeApplyScheduled else { return }
        sizeApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizeApplyScheduled = false
            guard let pendingSize = self.pendingSize else { return }
            self.applyPillSize(pendingSize)
        }
    }

    func relayoutPill() {
        let size: CGSize
        if pillSize.width > 1, pillSize.height > 1 {
            size = pillSize
        } else {
            size = CGSize(width: rootView.state.collapsedWidth, height: rootView.state.collapsedHeight)
        }
        applyPillSize(size)
    }

    func syncPointer() {
        guard !isRefreshingTracking, let local = currentLocalMouseLocation() else { return }
        let inside = pillContains(local)
        if window?.ignoresMouseEvents != !inside {
            window?.ignoresMouseEvents = !inside
        }
        guard inside != pointerInsidePill else { return }
        pointerInsidePill = inside
        onHoverChange?(inside)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let rect = interactiveRect
        guard rect.width > 1, rect.height > 1 else { return }

        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isRefreshingTracking else { return }
        syncPointer()
    }

    override func mouseExited(with event: NSEvent) {
        guard !isRefreshingTracking else { return }
        syncPointer()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isRefreshingTracking else { return }
        syncPointer()
    }

    private func applyPillSize(_ size: CGSize) {
        guard bounds.width > 1, bounds.height > 1, size.width > 1, size.height > 1 else { return }

        pillSize = size
        let rect = visualRect(for: size)
        let radius = rootView.state.cornerRadius(forHeight: size.height)
        let moved = abs(rect.minX - pillRect.minX) > 0.5
            || abs(rect.minY - pillRect.minY) > 0.5
            || abs(rect.width - pillRect.width) > 0.5
            || abs(rect.height - pillRect.height) > 0.5
            || abs(radius - bottomRadius) > 0.5
        guard moved else { return }

        pillRect = rect
        bottomRadius = radius
        isRefreshingTracking = true
        updateTrackingAreas()
        isRefreshingTracking = false
        syncPointer()
    }

    private func pillContains(_ point: NSPoint) -> Bool {
        let rect = interactiveRect
        guard rect.width > 1, rect.height > 1 else { return false }
        return makePillPath(in: rect, radius: bottomRadius).contains(point)
    }

    private var interactiveRect: CGRect {
        let visual = pillRect.width > 1 ? pillRect : collapsedVisualRect
        guard visual.width > 1, visual.height > 1 else { return .zero }
        if isFlipped {
            return CGRect(x: visual.minX, y: visual.minY, width: visual.width, height: visual.height + hoverOverflow)
        }
        return CGRect(
            x: visual.minX,
            y: visual.minY - hoverOverflow,
            width: visual.width,
            height: visual.height + hoverOverflow
        )
    }

    private var collapsedVisualRect: CGRect {
        let state = rootView.state
        return visualRect(for: CGSize(width: state.collapsedWidth, height: state.collapsedHeight))
    }

    /// NSHostingView tem origem no topo. A pílula fica ancorada nesse topo, não na base da janela.
    private func visualRect(for size: CGSize) -> CGRect {
        let width = min(max(size.width, 1), bounds.width)
        let height = min(max(size.height, 1), bounds.height)
        let y = isFlipped ? 0 : bounds.height - height
        return CGRect(
            x: (bounds.width - width) / 2,
            y: y,
            width: width,
            height: height
        )
    }

    private func currentLocalMouseLocation() -> NSPoint? {
        guard let window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(inWindow, from: nil)
    }

    private func makePillPath(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        guard r >= 0.5 else {
            path.appendRect(rect)
            return path
        }

        if isFlipped {
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - r))
            path.appendArc(
                from: NSPoint(x: rect.maxX, y: rect.maxY),
                to: NSPoint(x: rect.maxX - r, y: rect.maxY),
                radius: r
            )
            path.line(to: NSPoint(x: rect.minX + r, y: rect.maxY))
            path.appendArc(
                from: NSPoint(x: rect.minX, y: rect.maxY),
                to: NSPoint(x: rect.minX, y: rect.maxY - r),
                radius: r
            )
        } else {
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
            path.appendArc(
                from: NSPoint(x: rect.maxX, y: rect.minY),
                to: NSPoint(x: rect.maxX - r, y: rect.minY),
                radius: r
            )
            path.line(to: NSPoint(x: rect.minX + r, y: rect.minY))
            path.appendArc(
                from: NSPoint(x: rect.minX, y: rect.minY),
                to: NSPoint(x: rect.minX, y: rect.minY + r),
                radius: r
            )
        }
        path.close()
        return path
    }
}

final class NotchWindowController: NSObject {
    private let state = NotchState()
    private let panel: NotchPanel
    private let hostingView: NotchHostingView
    private var isExpanded = false
    private var collapseTask: Task<Void, Never>?
    private var pointerTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let expandedBody: CGFloat = 124
    private static let expandedWidth: CGFloat = 380

    override init() {
        let initial = NSRect(x: 0, y: 0, width: Self.expandedWidth, height: Self.expandedBody)
        panel = NotchPanel(contentRect: initial)
        hostingView = NotchHostingView(rootView: ContentView(state: state))
        super.init()

        hostingView.safeAreaRegions = []
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onHoverChange = { [weak self] hovering in
            self?.setExpanded(hovering)
        }
        state.onPillSizeChange = { [weak self] size in
            self?.hostingView.updatePillSize(size)
        }
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(relayout),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        layout()
    }

    func show() {
        layout()
        startPointerTracking()
        panel.orderFrontRegardless()
    }

    private func setExpanded(_ expanded: Bool) {
        collapseTask?.cancel()

        guard expanded else {
            guard isExpanded else { return }
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard let self, !Task.isCancelled else { return }
                guard !self.hostingView.pointerInsidePill else { return }
                self.apply(expanded: false)
            }
            return
        }

        guard !isExpanded else { return }
        apply(expanded: true)
    }

    private func apply(expanded: Bool) {
        isExpanded = expanded
        withAnimation(.smooth(duration: NotchState.animationDuration)) {
            state.isExpanded = expanded
        }
    }

    @objc private func relayout() {
        layout()
    }

    @objc private func spaceChanged() {
        panel.orderFrontRegardless()
    }

    private func layout() {
        guard let screen = Self.targetScreen() else { return }

        let anchor = Self.notchAnchor(on: screen)
        let menuBar = Self.resolvedMenuBarHeight(anchor.menuBarHeight)
        let collapsedWidth = anchor.width
        let canvasWidth = max(Self.expandedWidth, collapsedWidth)
        let canvasHeight = menuBar + Self.expandedBody
        let frame = NSRect(
            x: anchor.centerX - canvasWidth / 2,
            y: screen.frame.maxY - canvasHeight,
            width: canvasWidth,
            height: canvasHeight
        )
        panel.setFrame(frame, display: true)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.collapsedWidth = collapsedWidth
            state.expandedWidth = canvasWidth
            state.collapsedHeight = menuBar
            state.expandedHeight = canvasHeight
        }

        hostingView.relayoutPill()
    }

    private func startPointerTracking() {
        guard pointerTimer == nil else { return }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.hostingView.syncPointer()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.hostingView.syncPointer()
            return event
        }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.hostingView.syncPointer()
        }
        timer.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private static func resolvedMenuBarHeight(_ measured: CGFloat) -> CGFloat {
        measured > 1 ? measured : 24
    }

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Centro e largura do recorte físico. Em telas sem notch, usa o meio da tela.
    private static func notchAnchor(on screen: NSScreen) -> (centerX: CGFloat, width: CGFloat, menuBarHeight: CGFloat) {
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let gap = right.minX - left.maxX
            if gap >= 120 && gap <= 420 {
                let center = (left.maxX + right.minX) / 2
                return (center, gap, menuBar)
            }
        }

        return (screen.frame.midX, 200, menuBar)
    }
}
