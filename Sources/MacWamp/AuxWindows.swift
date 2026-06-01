import AppKit

final class EqualizerView: NSView {
    private let controller: WinampController
    private let skin = WinampSkin()
    private let pixelScale: CGFloat
    private var pressed: Region?
    private var changeID: UUID?

    private enum Region: Equatable { case close, on, auto, presets, preamp, band(Int), drag }

    init(frame: NSRect, controller: WinampController, pixelScale: CGFloat) {
        self.controller = controller
        self.pixelScale = pixelScale
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        changeID = controller.addChangeHandler { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let changeID { Task { @MainActor [weak controller] in controller?.removeChangeHandler(changeID) } } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        // Original EQMAIN.BMP top 0...116 is the live equalizer window.
        skin.eqmain.draw(src: CGRect(x: 0, y: 0, width: 275, height: 116), dst: CGRect(x: 0, y: 0, width: 275, height: 116))
        drawTitleButtons()
        drawOnAuto()
        drawPresets()
        drawGraph()
        drawSlider(which: 0, value: controller.eqPreamp)
        for i in 0..<10 { drawSlider(which: i + 1, value: controller.eqBands[i]) }
        ctx.restoreGState()
    }

    private func drawTitleButtons() {
        if pressed == .close {
            skin.eqmain.draw(src: CGRect(x: 0, y: 125, width: 9, height: 9), dst: CGRect(x: 264, y: 3, width: 9, height: 9))
        }
    }

    private func drawOnAuto() {
        let onPressed = pressed == .on
        let autoPressed = pressed == .auto
        skin.eqmain.draw(src: CGRect(x: 10 + (onPressed ? 118 : 0) + (controller.eqEnabled ? 59 : 0), y: 119, width: 25, height: 12), dst: CGRect(x: 14, y: 18, width: 25, height: 12))
        skin.eqmain.draw(src: CGRect(x: 35 + (autoPressed ? 118 : 0) + (controller.eqAuto ? 59 : 0), y: 119, width: 33, height: 12), dst: CGRect(x: 39, y: 18, width: 33, height: 12))
    }

    private func drawPresets() {
        skin.eqmain.draw(src: CGRect(x: 224, y: pressed == .presets ? 176 : 164, width: 44, height: 12), dst: CGRect(x: 217, y: 18, width: 44, height: 12))
    }

    private func drawSlider(which: Int, value: Int) {
        let xp = which == 0 ? 21 : 78 + (96 - 78) * (which - 1)
        let top = 38
        let pos = value.clamped(0, 64)
        let n = 27 - ((pos * 28) / 64)
        let srcX = n < 14 ? 13 + n * 15 : 13 + (n - 14) * 15
        let srcY = n < 14 ? 164 : 229
        skin.eqmain.draw(src: CGRect(x: srcX, y: srcY, width: 14, height: 63), dst: CGRect(x: xp, y: top, width: 14, height: 63))
        let thumbY = top + 63 - 12 - ((63 - pos) * (63 - 11)) / 64
        let isPressed: Bool
        if case .preamp = pressed, which == 0 { isPressed = true }
        else if case let .band(i) = pressed, i + 1 == which { isPressed = true }
        else { isPressed = false }
        skin.eqmain.draw(src: CGRect(x: 0, y: isPressed ? 176 : 164, width: 11, height: 11), dst: CGRect(x: xp + 1, y: thumbY, width: 11, height: 11))
    }

    private func drawGraph() {
        skin.eqmain.draw(src: CGRect(x: 0, y: 294, width: 113, height: 19), dst: CGRect(x: 86, y: 17, width: 113, height: 19))
        let points = controller.eqBands.map { CGFloat(18 - (($0.clamped(0, 64) * 18) / 64)) }
        NSColor(calibratedRed: 33/255, green: 239/255, blue: 33/255, alpha: controller.eqEnabled ? 1 : 0.45).setStroke()
        let path = NSBezierPath()
        for x in 0..<109 {
            let t = CGFloat(x) / 108 * 9
            let i = min(8, max(0, Int(t)))
            let f = t - CGFloat(i)
            let y = points[i] * (1 - f) + points[i + 1] * f
            let pt = NSPoint(x: 88 + CGFloat(x), y: 17 + y)
            x == 0 ? path.move(to: pt) : path.line(to: pt)
        }
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = winampPoint(event)
        pressed = hit(p)
        if pressed == .drag { window?.performDrag(with: event) } else { updateContinuous(point: p) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { updateContinuous(point: winampPoint(event)) }

    override func mouseUp(with event: NSEvent) {
        let r = pressed
        pressed = nil
        defer { needsDisplay = true }
        switch r {
        case .close:
            controller.eqWindow?.orderOut(nil); controller.eqVisible = false
        case .on: controller.eqEnabled.toggle()
        case .auto: controller.eqAuto.toggle()
        case .presets: controller.resetEqualizer()
        default: break
        }
    }

    private func updateContinuous(point p: CGPoint) {
        guard let pressed else { return }
        let val = Int(((101 - p.y).clamped(0, 63) / 63) * 64)
        switch pressed {
        case .preamp: controller.eqPreamp = val
        case let .band(i): controller.setEqBand(i, value: val)
        default: break
        }
    }

    private func hit(_ p: CGPoint) -> Region {
        if rect(264, 3, 9, 9).contains(p) { return .close }
        if rect(14, 18, 25, 12).contains(p) { return .on }
        if rect(39, 18, 33, 12).contains(p) { return .auto }
        if rect(217, 18, 44, 12).contains(p) { return .presets }
        if rect(21, 38, 14, 63).contains(p) { return .preamp }
        for i in 0..<10 where rect(CGFloat(78 + 18 * i), 38, 14, 63).contains(p) { return .band(i) }
        return .drag
    }

    private func winampPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / pixelScale, y: p.y / pixelScale)
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

final class PlaylistView: NSView {
    private let controller: WinampController
    private let skin = WinampSkin()
    private let pixelScale: CGFloat
    private var pressed: Region?
    private var selected: Int?
    private var changeID: UUID?

    private enum Region: Equatable { case close, add, remove, select, misc, list, scrollbar, drag }

    init(frame: NSRect, controller: WinampController, pixelScale: CGFloat) {
        self.controller = controller
        self.pixelScale = pixelScale
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        registerForDraggedTypes([.fileURL])
        changeID = controller.addChangeHandler { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let changeID { Task { @MainActor [weak controller] in controller?.removeChangeHandler(changeID) } } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        drawClassicFrame()
        drawEntries()
        drawBottomTime()
        ctx.restoreGState()
    }

    private func drawClassicFrame() {
        // Fixed 275x116 classic playlist: top title strip + middle list area + bottom controls.
        skin.pledit.draw(src: CGRect(x: 0, y: window?.isKeyWindow == false ? 21 : 0, width: 25, height: 20), dst: CGRect(x: 0, y: 0, width: 25, height: 20))
        skin.pledit.draw(src: CGRect(x: 26, y: window?.isKeyWindow == false ? 21 : 0, width: 100, height: 20), dst: CGRect(x: 25, y: 0, width: 100, height: 20))
        skin.pledit.draw(src: CGRect(x: 127, y: window?.isKeyWindow == false ? 21 : 0, width: 25, height: 20), dst: CGRect(x: 125, y: 0, width: 125, height: 20))
        skin.pledit.draw(src: CGRect(x: 153, y: window?.isKeyWindow == false ? 21 : 0, width: 25, height: 20), dst: CGRect(x: 250, y: 0, width: 25, height: 20))
        skin.pledit.draw(src: CGRect(x: 0, y: 42, width: 12, height: 29), dst: CGRect(x: 0, y: 20, width: 12, height: 58))
        skin.pledit.draw(src: CGRect(x: 31, y: 42, width: 20, height: 29), dst: CGRect(x: 255, y: 20, width: 20, height: 58))
        skin.pledit.draw(src: CGRect(x: 179, y: 0, width: 25, height: 38), dst: CGRect(x: 0, y: 78, width: 25, height: 38))
        skin.pledit.draw(src: CGRect(x: 205, y: 0, width: 75, height: 38), dst: CGRect(x: 25, y: 78, width: 175, height: 38))
        skin.pledit.draw(src: CGRect(x: 72, y: 42, width: 50, height: 38), dst: CGRect(x: 200, y: 78, width: 50, height: 38))
        skin.pledit.draw(src: CGRect(x: 126, y: 42, width: 25, height: 38), dst: CGRect(x: 250, y: 78, width: 25, height: 38))
        if pressed == .close { skin.pledit.draw(src: CGRect(x: 52, y: 42, width: 9, height: 9), dst: CGRect(x: 264, y: 3, width: 9, height: 9)) }
    }

    private func drawEntries() {
        let listRect = NSRect(x: 12, y: 22, width: 243, height: 55)
        NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.92).setFill()
        listRect.fill()
        let visible = 5
        let start = controller.playlistScroll.clamped(0, max(0, controller.playlist.count - visible))
        for row in 0..<visible {
            let idx = start + row
            let y = 24 + row * 10
            guard controller.playlist.indices.contains(idx) else { continue }
            let isCurrent = idx == controller.currentPlaylistIndex
            let isSelected = idx == selected
            if isSelected {
                NSColor(calibratedRed: 0/255, green: 64/255, blue: 128/255, alpha: 1).setFill()
                NSRect(x: 12, y: y - 1, width: 243, height: 10).fill()
            }
            let prefix = String(format: "%02d. ", idx + 1)
            let duration = controller.playlist[idx].duration.map { formatTime($0) } ?? "--:--"
            drawText(prefix + controller.playlist[idx].title, x: 14, y: y, maxChars: 38, current: isCurrent)
            drawText(duration, x: 230, y: y, maxChars: 5, current: isCurrent)
        }
    }

    private func drawBottomTime() {
        let total = controller.playlist.compactMap { $0.duration }.reduce(0, +)
        drawText("\(controller.playlist.count) TRACKS", x: 112, y: 82, maxChars: 18, current: false)
        drawText(formatTime(total), x: 228, y: 82, maxChars: 7, current: false)
    }

    private func drawText(_ text: String, x: Int, y: Int, maxChars: Int, current: Bool) {
        var dx = x
        let color = current ? NSColor(calibratedRed: 33/255, green: 239/255, blue: 33/255, alpha: 1) : NSColor(calibratedRed: 0, green: 210/255, blue: 0, alpha: 1)
        color.setFill()
        for ch in Array(text.uppercased()).prefix(maxChars) {
            let c = skin.xyForWinampFont(ch)
            skin.text.draw(src: CGRect(x: c.0, y: c.1, width: 5, height: 6), dst: CGRect(x: dx, y: y, width: 5, height: 6))
            dx += 5
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = winampPoint(event)
        pressed = hit(p)
        if pressed == .drag { window?.performDrag(with: event) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let r = pressed
        let p = winampPoint(event)
        pressed = nil
        defer { needsDisplay = true }
        switch r {
        case .close:
            controller.playlistWindow?.orderOut(nil); controller.playlistVisible = false
        case .add: controller.openPlaylistPanel()
        case .remove: if let selected { controller.removePlaylistItem(at: selected); self.selected = nil }
        case .misc: controller.clearPlaylist()
        case .select: selected = controller.currentPlaylistIndex
        case .list:
            let row = Int((p.y - 22) / 10)
            let idx = controller.playlistScroll + row
            if controller.playlist.indices.contains(idx) { selected = idx; if event.clickCount >= 2 { controller.playPlaylistItem(at: idx) } }
        case .scrollbar:
            controller.playlistScroll = Int(((p.y - 22).clamped(0, 55) / 55) * CGFloat(max(0, controller.playlist.count - 5)))
        default: break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        controller.playlistScroll += event.scrollingDeltaY > 0 ? -1 : 1
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        controller.addToPlaylist(urls: urls, autoplayFirstIfEmpty: true)
        return !urls.isEmpty
    }

    private func hit(_ p: CGPoint) -> Region {
        if rect(264, 3, 9, 9).contains(p) { return .close }
        if rect(12, 22, 243, 55).contains(p) { return .list }
        if rect(255, 22, 20, 55).contains(p) { return .scrollbar }
        if rect(11, 88, 40, 14).contains(p) { return .add }
        if rect(52, 88, 40, 14).contains(p) { return .remove }
        if rect(94, 88, 40, 14).contains(p) { return .select }
        if rect(136, 88, 40, 14).contains(p) { return .misc }
        return .drag
    }

    private func formatTime(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
    private func winampPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / pixelScale, y: p.y / pixelScale)
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
}
