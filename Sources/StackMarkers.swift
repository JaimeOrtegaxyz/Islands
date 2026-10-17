import AppKit
import IslandsCore
import UniformTypeIdentifiers

/// One window in a stack, as its marker shows it.
struct StackMarkerMember: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
}

/// Draws each stack's marker in the band Islands leaves above it (see `StackMarkerStyle`),
/// plus the slim style's switcher. Presentation only: clicks and drags come back through
/// `onSelect` / `onReorder`, and `WindowManager` decides what they do.
///
/// Markers are non-activating panels at the normal window level. They sit beside the stack,
/// never over it, so they never fight the windows they describe for z-order — the fight that
/// made real-window peeks flicker can't happen here. Each marker is kept just above its stack's
/// front (`restack`), so a window from an overlapping slot covers it only when that window is
/// also above the stack.
final class StackMarkerController {
    var onSelect: ((_ zoneKey: String, _ windowID: CGWindowID) -> Void)?
    /// The stack's members in their new order after a drag.
    var onReorder: ((_ zoneKey: String, _ order: [CGWindowID]) -> Void)?

    var style: StackMarkerStyle {
        didSet { if style != oldValue { removeAll() } }
    }

    private struct Marker {
        let panel: MarkerPanel
        var slot: CGRect
        var snapWidths: [CGFloat]
        var members: [StackMarkerMember]
        var frontID: CGWindowID
    }

    private var markers: [String: Marker] = [:]
    private let visuals = AppVisuals()
    private var switcherZone: String?
    private lazy var switcher: SwitcherPanel = {
        let panel = SwitcherPanel()
        panel.onSelect = { [weak self] index in
            guard let self, let zoneKey = self.switcherZone else { return }
            self.select(index, in: zoneKey)
        }
        panel.onReorder = { [weak self] from, to in
            guard let self, let zoneKey = self.switcherZone else { return }
            self.reorder(from: from, to: to, in: zoneKey)
        }
        return panel
    }()

    init(style: StackMarkerStyle) {
        self.style = style
    }

    /// Show or refresh a stack's marker. `slot` is the stack's whole slot (band included) in
    /// AppKit screen coordinates; `snapWidths` are the window widths the snap profile allows on
    /// its screen, for the tab strip to end on. A no-op when nothing changed, so it is cheap to
    /// call often.
    func show(zoneKey: String, slot: CGRect, snapWidths: [CGFloat], members: [StackMarkerMember], frontID: CGWindowID) {
        if let existing = markers[zoneKey], existing.panel.isVisible, existing.slot == slot,
           existing.snapWidths == snapWidths, existing.members == members, existing.frontID == frontID {
            return
        }
        let panel = markers[zoneKey]?.panel ?? makePanel(zoneKey: zoneKey)
        markers[zoneKey] = Marker(panel: panel, slot: slot, snapWidths: snapWidths, members: members, frontID: frontID)
        render(zoneKey)
        if switcherZone == zoneKey, switcher.isShowing { refreshSwitcher(zoneKey) }
    }

    /// Move a stack's highlight to `frontID` without re-reading anything else.
    func setFront(zoneKey: String, frontID: CGWindowID) {
        guard var marker = markers[zoneKey], marker.frontID != frontID,
              marker.members.contains(where: { $0.id == frontID }) else { return }
        marker.frontID = frontID
        markers[zoneKey] = marker
        render(zoneKey)
        if switcherZone == zoneKey, switcher.isShowing { refreshSwitcher(zoneKey) }
    }

    /// Put a stack's marker directly above its front window. Only our own panel moves; the
    /// windows are untouched.
    func restack(zoneKey: String) {
        guard let marker = markers[zoneKey], marker.panel.isVisible else { return }
        marker.panel.order(.above, relativeTo: Int(marker.frontID))
    }

    func remove(zoneKey: String) {
        guard let marker = markers.removeValue(forKey: zoneKey) else { return }
        marker.panel.orderOut(nil)
        if switcherZone == zoneKey { switcher.dismiss() }
        visuals.prune(keeping: Set(markers.values.flatMap { $0.members.map(\.pid) }))
    }

    func removeAll() {
        for zoneKey in Array(markers.keys) { remove(zoneKey: zoneKey) }
    }

    /// The slim style's switcher: the stack's apps, large, over the stack for a moment after a
    /// switch. It stays while the pointer is on it, and its icons can be dragged to reorder.
    func showSwitcher(zoneKey: String) {
        guard style == .slim, let marker = markers[zoneKey] else { return }
        switcherZone = zoneKey
        let (entries, front) = content(of: marker)
        switcher.present(entries: entries, frontIndex: front, over: stackArea(of: marker.slot))
    }

    // MARK: Rendering

    private func makePanel(zoneKey: String) -> MarkerPanel {
        let panel = MarkerPanel()
        switch style {
        case .tabs:
            let tabs = TabsView()
            tabs.onSelect = { [weak self] index in self?.select(index, in: zoneKey) }
            tabs.onReorder = { [weak self] from, to in self?.reorder(from: from, to: to, in: zoneKey) }
            panel.install(content: tabs, backdrop: makeBackdrop(material: .menu, cornerRadius: (style.bandHeight - 2) / 2))
        case .slim:
            let dashes = DashesView()
            dashes.onSelect = { [weak self] index in self?.select(index, in: zoneKey) }
            panel.install(content: dashes, backdrop: nil)
        }
        return panel
    }

    private func render(_ zoneKey: String) {
        guard let marker = markers[zoneKey] else { return }
        let (entries, front) = content(of: marker)
        let slot = marker.slot
        let band = style.bandHeight
        let wasVisible = marker.panel.isVisible

        switch style {
        case .tabs:
            let reach = StackMarkerLayout.tabStripReach(count: entries.count, stackWidth: slot.width, snapWidths: marker.snapWidths)
            let tabWidth = StackMarkerLayout.tabWidth(count: entries.count, reach: reach)
            let height = band - 2
            marker.panel.setFrame(NSRect(
                x: slot.minX + StackMarkerLayout.tabStripInset,
                y: slot.maxY - 1 - height,
                width: StackMarkerLayout.tabStripWidth(count: entries.count, tabWidth: tabWidth),
                height: height
            ), display: false)
            (marker.panel.content as? TabsView)?.update(entries: entries, frontIndex: front, tabWidth: tabWidth, animated: wasVisible)
        case .slim:
            marker.panel.setFrame(NSRect(
                x: slot.minX + StackMarkerLayout.dashInset,
                y: slot.maxY - band,
                width: StackMarkerLayout.dashRowWidth(count: entries.count),
                height: band
            ), display: false)
            (marker.panel.content as? DashesView)?.update(entries: entries, frontIndex: front)
        }

        if !wasVisible {
            marker.panel.orderFrontRegardless()
            restack(zoneKey: zoneKey)
        }
    }

    private func refreshSwitcher(_ zoneKey: String) {
        guard let marker = markers[zoneKey] else { return }
        let (entries, front) = content(of: marker)
        switcher.update(entries: entries, frontIndex: front)
    }

    private func content(of marker: Marker) -> (entries: [MarkerEntry], front: Int) {
        let entries = marker.members.map(visuals.entry(for:))
        let front = marker.members.firstIndex { $0.id == marker.frontID } ?? 0
        return (entries, front)
    }

    /// The part of a slot the stack's windows occupy (below the band).
    private func stackArea(of slot: CGRect) -> CGRect {
        CGRect(x: slot.minX, y: slot.minY, width: slot.width, height: slot.height - style.bandHeight)
    }

    private func select(_ index: Int, in zoneKey: String) {
        guard let members = markers[zoneKey]?.members, members.indices.contains(index) else { return }
        onSelect?(zoneKey, members[index].id)
    }

    private func reorder(from: Int, to: Int, in zoneKey: String) {
        guard let members = markers[zoneKey]?.members else { return }
        onReorder?(zoneKey, StackMarkerLayout.moving(members.map(\.id), from: from, to: to))
    }
}

// MARK: - App visuals

/// What a marker draws for one window.
private struct MarkerEntry {
    let title: String
    let appName: String
    let icon: NSImage
    /// The app's colour for the slim marker; nil when its icon has none (use `MarkerPalette.ink`).
    let tint: NSColor?

    var label: String { title.isEmpty ? appName : title }
}

/// Icons, names and tints per app, computed once per process.
private final class AppVisuals {
    private struct Visual {
        let name: String
        let icon: NSImage
        let tint: NSColor?
    }

    private var cache: [pid_t: Visual] = [:]

    func entry(for member: StackMarkerMember) -> MarkerEntry {
        let visual = visual(for: member.pid)
        return MarkerEntry(title: member.title, appName: visual.name, icon: visual.icon, tint: visual.tint)
    }

    func prune(keeping pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }

    private func visual(for pid: pid_t) -> Visual {
        if let cached = cache[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        let icon = app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        let visual = Visual(name: app?.localizedName ?? "", icon: icon, tint: Self.tint(of: icon))
        cache[pid] = visual
        return visual
    }

    /// The icon's dominant colour (see `IconTint`), nudged so a 4pt dash of it stays visible.
    private static func tint(of icon: NSImage) -> NSColor? {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep), let data = rep.bitmapData else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var pixels: [IconTint.Pixel] = []
        pixels.reserveCapacity(side * side)
        for y in 0..<side {
            for x in 0..<side {
                let offset = y * rep.bytesPerRow + x * 4
                let alpha = CGFloat(data[offset + 3]) / 255
                guard alpha > 0 else { continue }
                // The rep is premultiplied; IconTint wants straight colour.
                pixels.append(IconTint.Pixel(
                    r: min(1, CGFloat(data[offset]) / 255 / alpha),
                    g: min(1, CGFloat(data[offset + 1]) / 255 / alpha),
                    b: min(1, CGFloat(data[offset + 2]) / 255 / alpha),
                    a: alpha
                ))
            }
        }

        guard let rgb = IconTint.dominantColor(of: pixels),
              let color = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1).usingColorSpace(.sRGB) else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: max(saturation, 0.45), brightness: min(max(brightness, 0.55), 0.92), alpha: 1)
    }
}

// MARK: - Palette

private enum MarkerPalette {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static let stripEdge = dynamic(NSColor(white: 0, alpha: 0.12), NSColor(white: 1, alpha: 0.14))
    static let selection = dynamic(.white, srgb(0x5E5E62))
    static let selectionShadow = dynamic(NSColor(white: 0, alpha: 0.24), NSColor(white: 0, alpha: 0.45))
    static let hover = dynamic(NSColor(white: 0, alpha: 0.06), NSColor(white: 1, alpha: 0.08))
    /// Islands teal: drop indicators.
    static let accent = dynamic(srgb(0x146F80), srgb(0x6CCFDB))
    /// The front dash for an app whose icon has no colour of its own.
    static let ink = dynamic(srgb(0x3A3A3C), srgb(0xE5E5EA))
    static let dashIdle = dynamic(NSColor(white: 1, alpha: 0.72), NSColor(white: 1, alpha: 0.30))
    static let dashEdge = dynamic(NSColor(white: 0, alpha: 0.22), NSColor(white: 0, alpha: 0.40))
    static let switcherSelection = dynamic(NSColor(white: 0, alpha: 0.10), NSColor(white: 1, alpha: 0.16))
}

/// A material backdrop clipped to a rounded rect. `state = .active` because Islands is never
/// the active app, and an inactive material would grey out.
private func makeBackdrop(material: NSVisualEffectView.Material, cornerRadius: CGFloat) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = .behindWindow
    view.state = .active
    let edge = cornerRadius * 2 + 1
    let mask = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        return true
    }
    mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
    mask.resizingMode = .stretch
    view.maskImage = mask
    return view
}

// MARK: - Panels

/// A borderless, non-activating panel: clicking it never makes Islands the active app.
private class OverlayPanel: NSPanel {
    init(level: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MarkerPanel: OverlayPanel {
    private(set) var content: NSView?

    init() {
        super.init(level: .normal)
        hasShadow = false
    }

    func install(content: NSView, backdrop: NSVisualEffectView?) {
        let container = NSView()
        contentView = container
        if let backdrop {
            backdrop.frame = container.bounds
            backdrop.autoresizingMask = [.width, .height]
            container.addSubview(backdrop)
        }
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        self.content = content
    }
}

/// Press, then either release (a click) or move past a small threshold (a drag to reorder).
private struct DragTracker {
    private(set) var from: Int?
    private(set) var target: Int?
    private(set) var isDragging = false
    private var origin: NSPoint = .zero

    mutating func begin(at index: Int, point: NSPoint) {
        self = DragTracker()
        from = index
        target = index
        origin = point
    }

    mutating func move(to point: NSPoint, index: Int) {
        guard from != nil else { return }
        if !isDragging, hypot(point.x - origin.x, point.y - origin.y) > 4 { isDragging = true }
        if isDragging { target = index }
    }

    mutating func reset() {
        self = DragTracker()
    }

    /// The drop indicator's side: before the target when dragging leftwards, after it otherwise.
    var dropsBeforeTarget: Bool {
        guard let from, let target else { return false }
        return from > target
    }

    var showsDropIndicator: Bool {
        isDragging && target != nil && target != from
    }
}

// MARK: - Tabs

private final class TabsView: NSView {
    var onSelect: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?

    private var entries: [MarkerEntry] = []
    private var frontIndex = 0
    private var tabWidth: CGFloat = 0
    private var hoverIndex: Int?
    private var drag = DragTracker()

    /// Left edge of the highlight, animated so a switch slides it to the new front.
    @objc dynamic var selectionOffset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "selectionOffset" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    func update(entries: [MarkerEntry], frontIndex: Int, tabWidth: CGFloat, animated: Bool) {
        self.entries = entries
        self.frontIndex = frontIndex
        self.tabWidth = tabWidth
        let offset = CGFloat(frontIndex) * tabWidth
        if animated, abs(offset - selectionOffset) > 0.5 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                animator().selectionOffset = offset
            }
        } else {
            selectionOffset = offset
        }
        needsDisplay = true
    }

    private var tabHeight: CGFloat { bounds.height - 2 * StackMarkerLayout.tabStripPadding }

    private func tabRect(_ index: Int) -> NSRect {
        let padding = StackMarkerLayout.tabStripPadding
        return NSRect(x: padding + CGFloat(index) * tabWidth, y: padding, width: tabWidth, height: tabHeight)
    }

    private func index(at point: NSPoint) -> Int {
        StackMarkerLayout.cellIndex(at: point.x - StackMarkerLayout.tabStripPadding, cellWidth: tabWidth, count: entries.count)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = tabHeight / 2

        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        edge.lineWidth = 0.5
        MarkerPalette.stripEdge.setStroke()
        edge.stroke()

        if let hover = hoverIndex, hover != frontIndex, !drag.isDragging {
            MarkerPalette.hover.setFill()
            NSBezierPath(roundedRect: tabRect(hover), xRadius: radius, yRadius: radius).fill()
        }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = MarkerPalette.selectionShadow
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.5
        shadow.set()
        MarkerPalette.selection.setFill()
        let selection = NSRect(x: StackMarkerLayout.tabStripPadding + selectionOffset, y: StackMarkerLayout.tabStripPadding, width: tabWidth, height: tabHeight)
        NSBezierPath(roundedRect: selection, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        let showsTitles = StackMarkerLayout.showsTabTitles(tabWidth: tabWidth)
        let iconSize = min(14, max(8, tabHeight - 2))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        for (index, entry) in entries.enumerated() {
            let rect = tabRect(index)
            let isFront = index == frontIndex
            let fraction: CGFloat = drag.isDragging && drag.from == index ? 0.4 : 1

            var title: NSAttributedString?
            var titleWidth: CGFloat = 0
            if showsTitles {
                let color = isFront ? NSColor.labelColor : NSColor.secondaryLabelColor
                let text = NSAttributedString(string: entry.label, attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: isFront ? .semibold : .medium),
                    .foregroundColor: color.withAlphaComponent(fraction),
                    .paragraphStyle: paragraph,
                ])
                titleWidth = min(ceil(text.size().width), max(0, rect.width - 16 - iconSize - 5))
                if titleWidth > 0 { title = text }
            }

            let contentWidth = iconSize + (title == nil ? 0 : 5 + titleWidth)
            var x = rect.minX + (rect.width - contentWidth) / 2
            entry.icon.draw(
                in: NSRect(x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize),
                from: .zero, operation: .sourceOver, fraction: fraction, respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            x += iconSize + 5
            if let title {
                let height = ceil(title.size().height)
                title.draw(
                    with: NSRect(x: x, y: rect.midY - height / 2, width: titleWidth, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
                )
            }
        }

        if drag.showsDropIndicator, let target = drag.target {
            let rect = tabRect(target)
            let x = drag.dropsBeforeTarget ? rect.minX : rect.maxX - 2
            MarkerPalette.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: rect.minY + 2, width: 2, height: rect.height - 4), xRadius: 1, yRadius: 1).fill()
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let hover = index(at: convert(event.locationInWindow, from: nil))
        if hover != hoverIndex {
            hoverIndex = hover
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        drag.begin(at: index(at: point), point: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        drag.move(to: point, index: index(at: point))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let tracked = drag
        drag.reset()
        needsDisplay = true
        guard let from = tracked.from else { return }
        if tracked.isDragging {
            if let to = tracked.target, to != from { onReorder?(from, to) }
        } else {
            onSelect?(from)
        }
    }
}

// MARK: - Slim

private final class DashesView: NSView {
    var onSelect: ((Int) -> Void)?

    private var entries: [MarkerEntry] = []
    private var frontIndex = 0

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(entries: [MarkerEntry], frontIndex: Int) {
        self.entries = entries
        self.frontIndex = frontIndex
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let width = StackMarkerLayout.dashWidth(count: entries.count)
        let height = StackMarkerLayout.dashHeight
        for (index, entry) in entries.enumerated() {
            let rect = NSRect(
                x: CGFloat(index) * (width + StackMarkerLayout.dashSpacing),
                y: (bounds.height - height) / 2,
                width: width,
                height: height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = MarkerPalette.dashEdge
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            shadow.set()
            (index == frontIndex ? entry.tint ?? MarkerPalette.ink : MarkerPalette.dashIdle).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: height / 2, yRadius: height / 2)
            edge.lineWidth = 0.5
            MarkerPalette.dashEdge.setStroke()
            edge.stroke()
        }
    }

    // Claimed so the matching mouseUp comes back to this view.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onSelect?(StackMarkerLayout.cellIndex(
            at: point.x,
            cellWidth: StackMarkerLayout.dashWidth(count: entries.count),
            spacing: StackMarkerLayout.dashSpacing,
            count: entries.count
        ))
    }
}

// MARK: - Switcher

private final class SwitcherPanel: OverlayPanel {
    var onSelect: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    private(set) var isShowing = false

    private let content = SwitcherView()
    private var hideTimer: Timer?
    private var isHovered = false

    private static let lingerSeconds: TimeInterval = 1.4
    private static let fadeSeconds: TimeInterval = 0.16

    init() {
        // Over the stack it describes, so it must float above normal windows; it is only
        // ever up for a moment.
        super.init(level: .floating)
        hasShadow = true

        let container = NSView()
        contentView = container
        let backdrop = makeBackdrop(material: .popover, cornerRadius: 20)
        backdrop.frame = container.bounds
        backdrop.autoresizingMask = [.width, .height]
        container.addSubview(backdrop)
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)

        content.onSelect = { [weak self] index in self?.onSelect?(index) }
        content.onReorder = { [weak self] from, to in self?.onReorder?(from, to) }
        content.onHoverChange = { [weak self] hovered in
            guard let self else { return }
            self.isHovered = hovered
            hovered ? self.cancelHide() : self.scheduleHide()
        }
    }

    func present(entries: [MarkerEntry], frontIndex: Int, over area: CGRect) {
        content.update(entries: entries, frontIndex: frontIndex)
        let size = content.preferredSize
        setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
        invalidateShadow()

        // Also catches a switch landing mid fade-out: the fade's completion sees isShowing again.
        isShowing = true
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeSeconds
            animator().alphaValue = 1
        }
        scheduleHide()
    }

    /// New content in place (a reorder, a title change), keeping the panel centred where it is.
    func update(entries: [MarkerEntry], frontIndex: Int) {
        content.update(entries: entries, frontIndex: frontIndex)
        let size = content.preferredSize
        let center = NSPoint(x: frame.midX, y: frame.midY)
        setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }

    func dismiss() {
        cancelHide()
        guard isShowing else { return }
        isShowing = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeSeconds
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShowing else { return }
            self.orderOut(nil)
        })
    }

    private func scheduleHide() {
        cancelHide()
        guard !isHovered else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.lingerSeconds, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}

private final class SwitcherView: NSView {
    var onSelect: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private var entries: [MarkerEntry] = []
    private var frontIndex = 0
    private var drag = DragTracker()

    private static let cell: CGFloat = 56
    private static let icon: CGFloat = 42
    private static let spacing: CGFloat = 4
    private static let padding = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
    private static let titleGap: CGFloat = 8
    private static let captionGap: CGFloat = 3
    private static let maxTextWidth: CGFloat = 280

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(entries: [MarkerEntry], frontIndex: Int) {
        self.entries = entries
        self.frontIndex = frontIndex
        needsDisplay = true
    }

    private var rowWidth: CGFloat {
        CGFloat(entries.count) * Self.cell + CGFloat(max(0, entries.count - 1)) * Self.spacing
    }

    private var title: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let label = entries.indices.contains(frontIndex) ? entries[frontIndex].label : ""
        return NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    private var caption: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let appName = entries.indices.contains(frontIndex) ? entries[frontIndex].appName : ""
        return NSAttributedString(string: "\(appName) · \(frontIndex + 1) of \(entries.count)", attributes: [
            .font: NSFont.quicksand(11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
    }

    var preferredSize: NSSize {
        let textWidth = min(Self.maxTextWidth, max(ceil(title.size().width), ceil(caption.size().width)))
        let width = max(rowWidth, textWidth) + Self.padding.left + Self.padding.right
        let height = Self.padding.top + Self.cell + Self.titleGap + ceil(title.size().height)
            + Self.captionGap + ceil(caption.size().height) + Self.padding.bottom
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private var rowOrigin: NSPoint {
        NSPoint(x: (bounds.width - rowWidth) / 2, y: Self.padding.top)
    }

    private func cellRect(_ index: Int) -> NSRect {
        NSRect(x: rowOrigin.x + CGFloat(index) * (Self.cell + Self.spacing), y: rowOrigin.y, width: Self.cell, height: Self.cell)
    }

    private func index(at point: NSPoint) -> Int {
        StackMarkerLayout.cellIndex(at: point.x - rowOrigin.x, cellWidth: Self.cell, spacing: Self.spacing, count: entries.count)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, entry) in entries.enumerated() {
            let cell = cellRect(index)
            if index == frontIndex {
                MarkerPalette.switcherSelection.setFill()
                NSBezierPath(roundedRect: cell, xRadius: 13, yRadius: 13).fill()
            }
            let inset = (Self.cell - Self.icon) / 2
            entry.icon.draw(
                in: cell.insetBy(dx: inset, dy: inset),
                from: .zero, operation: .sourceOver,
                fraction: drag.isDragging && drag.from == index ? 0.4 : 1,
                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high]
            )
        }

        if drag.showsDropIndicator, let target = drag.target {
            let cell = cellRect(target)
            let x = drag.dropsBeforeTarget ? cell.minX - 3 : cell.maxX + 1
            MarkerPalette.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: cell.minY + 8, width: 2, height: cell.height - 16), xRadius: 1, yRadius: 1).fill()
        }

        let textWidth = bounds.width - Self.padding.left - Self.padding.right
        let title = self.title
        let titleHeight = ceil(title.size().height)
        let titleY = Self.padding.top + Self.cell + Self.titleGap
        title.draw(with: NSRect(x: Self.padding.left, y: titleY, width: textWidth, height: titleHeight),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let caption = self.caption
        caption.draw(with: NSRect(x: Self.padding.left, y: titleY + titleHeight + Self.captionGap, width: textWidth, height: ceil(caption.size().height)),
                     options: [.usesLineFragmentOrigin])
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rowRect = NSRect(origin: rowOrigin, size: NSSize(width: rowWidth, height: Self.cell))
        guard rowRect.contains(point) else { return }
        drag.begin(at: index(at: point), point: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        drag.move(to: point, index: index(at: point))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let tracked = drag
        drag.reset()
        needsDisplay = true
        guard let from = tracked.from else { return }
        if tracked.isDragging {
            if let to = tracked.target, to != from { onReorder?(from, to) }
        } else {
            onSelect?(from)
        }
    }
}
