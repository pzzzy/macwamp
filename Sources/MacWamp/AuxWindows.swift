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
        // Mouse event coordinates arrive bottom-origin for this borderless auxiliary view, while the
        // Winamp EQ artwork is drawn top-origin. Map the slider rail so dragging upward raises
        // the value and dragging downward lowers it.
        let val = Int(((p.y - 38).clamped(0, 63) / 63) * 64)
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
    private var resizeStartFrame: NSRect?
    private var resizeStartScreenPoint: NSPoint?

    private enum Region: Equatable { case close, add, remove, select, misc, list, scrollbar, resize, drag }

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

    private var classicSize: CGSize {
        CGSize(width: max(275, floor(bounds.width / pixelScale)),
               height: max(116, floor(bounds.height / pixelScale)))
    }
    private var listRows: Int { max(1, Int((classicSize.height - 60) / 10)) }
    private var listRect: CGRect { CGRect(x: 12, y: 20, width: classicSize.width - 32, height: classicSize.height - 58) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        drawClassicFrame(width: classicSize.width, height: classicSize.height)
        drawEntries()
        drawBottomTime(width: classicSize.width, height: classicSize.height)
        ctx.restoreGState()
    }

    private func drawClassicFrame(width w: CGFloat, height h: CGFloat) {
        let activeY: CGFloat = window?.isKeyWindow == false ? 21 : 0
        let bottomY = h - 38
        let sideHeight = h - 58

        // Original draw_pe.cpp scalable titlebar: left cap, stretch/tile middle, 100px title, more fill, right cap/buttons.
        skin.pledit.draw(src: CGRect(x: 0, y: activeY, width: 25, height: 20), dst: CGRect(x: 0, y: 0, width: 25, height: 20))
        drawTiled(src: CGRect(x: 127, y: activeY, width: 25, height: 20), dst: CGRect(x: 25, y: 0, width: max(0, (w - 150) / 2), height: 20))
        skin.pledit.draw(src: CGRect(x: 26, y: activeY, width: 100, height: 20), dst: CGRect(x: 25 + max(0, (w - 150) / 2), y: 0, width: 100, height: 20))
        drawTiled(src: CGRect(x: 127, y: activeY, width: 25, height: 20), dst: CGRect(x: 125 + max(0, (w - 150) / 2), y: 0, width: max(0, w - 25 - (125 + max(0, (w - 150) / 2))), height: 20))
        skin.pledit.draw(src: CGRect(x: 153, y: activeY, width: 25, height: 20), dst: CGRect(x: w - 25, y: 0, width: 25, height: 20))

        drawTiled(src: CGRect(x: 0, y: 42, width: 12, height: 29), dst: CGRect(x: 0, y: 20, width: 12, height: sideHeight))
        drawTiled(src: CGRect(x: 31, y: 42, width: 5, height: 29), dst: CGRect(x: w - 20, y: 20, width: 5, height: sideHeight))
        drawTiled(src: CGRect(x: 44, y: 42, width: 7, height: 29), dst: CGRect(x: w - 7, y: 20, width: 7, height: sideHeight))

        // Main list background bounded by the original left/scrollbar borders.
        NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.94).setFill()
        listRect.fill()

        // Original bottom strip: fixed controls, tiled middle, optional center chunk, fixed right strip.
        skin.pledit.draw(src: CGRect(x: 0, y: 72, width: 125, height: 38), dst: CGRect(x: 0, y: bottomY, width: 125, height: 38))
        let middleEnd = max(125, w - 150)
        drawTiled(src: CGRect(x: 179, y: 0, width: 25, height: 38), dst: CGRect(x: 125, y: bottomY, width: max(0, middleEnd - 125), height: 38))
        skin.pledit.draw(src: CGRect(x: 126, y: 72, width: 150, height: 38), dst: CGRect(x: w - 150, y: bottomY, width: 150, height: 38))

        drawScrollbar(width: w, height: h)
        if pressed == .close { skin.pledit.draw(src: CGRect(x: 52, y: 42, width: 9, height: 9), dst: CGRect(x: w - 11, y: 3, width: 9, height: 9)) }
    }

    private func drawScrollbar(width w: CGFloat, height h: CGFloat) {
        let track = CGRect(x: w - 15, y: 20, width: 8, height: h - 58)
        drawTiled(src: CGRect(x: 36, y: 42, width: 8, height: 29), dst: track)
        let extra = max(0, controller.playlist.count - listRows)
        guard extra > 0 else { return }
        let thumbH = max(CGFloat(18), min(track.height, track.height * CGFloat(listRows) / CGFloat(controller.playlist.count)))
        let maxScroll = max(1, extra)
        let thumbY = track.minY + (track.height - thumbH) * CGFloat(controller.playlistScroll.clamped(0, extra)) / CGFloat(maxScroll)
        skin.pledit.draw(src: CGRect(x: pressed == .scrollbar ? 61 : 52, y: 53, width: 8, height: 18), dst: CGRect(x: track.minX, y: thumbY, width: 8, height: thumbH))
    }

    private func drawEntries() {
        let rows = listRows
        let start = controller.playlistScroll.clamped(0, max(0, controller.playlist.count - rows))
        let titleChars = max(8, Int((listRect.width - 50) / 5))
        for row in 0..<rows {
            let idx = start + row
            let y = Int(listRect.minY) + 2 + row * 10
            guard controller.playlist.indices.contains(idx) else { continue }
            let isCurrent = idx == controller.currentPlaylistIndex
            let isSelected = idx == selected
            if isSelected {
                NSColor(calibratedRed: 0/255, green: 64/255, blue: 128/255, alpha: 1).setFill()
                NSRect(x: listRect.minX, y: CGFloat(y - 1), width: listRect.width, height: 10).fill()
            }
            let prefix = String(format: "%02d. ", idx + 1)
            let duration = controller.playlist[idx].duration.map { formatTime($0) } ?? "--:--"
            drawText(prefix + controller.playlist[idx].title, x: Int(listRect.minX) + 2, y: y, maxChars: titleChars, current: isCurrent)
            drawText(duration, x: Int(listRect.maxX) - 27, y: y, maxChars: 5, current: isCurrent)
        }
    }

    private func drawBottomTime(width w: CGFloat, height h: CGFloat) {
        let total = controller.playlist.compactMap { $0.duration }.reduce(0, +)
        let y = Int(h - 28)
        let status = "\(controller.playlist.count) TRACKS \(formatTime(total))"
        drawText(status, x: max(128, Int(w) - 143), y: y, maxChars: 19, current: false)
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

    private func drawTiled(src: CGRect, dst: CGRect) {
        guard dst.width > 0, dst.height > 0 else { return }
        var y = dst.minY
        while y < dst.maxY {
            let h = min(src.height, dst.maxY - y)
            var x = dst.minX
            while x < dst.maxX {
                let w = min(src.width, dst.maxX - x)
                skin.pledit.draw(src: CGRect(x: src.minX, y: src.minY, width: w, height: h), dst: CGRect(x: x, y: y, width: w, height: h))
                x += w
            }
            y += h
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = winampPoint(event)
        pressed = hit(p)
        if pressed == .resize {
            resizeStartFrame = window?.frame
            resizeStartScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        } else if pressed == .drag {
            window?.performDrag(with: event)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if pressed == .resize, let window, let startFrame = resizeStartFrame, let startPoint = resizeStartScreenPoint {
            let now = window.convertPoint(toScreen: event.locationInWindow)
            let dx = now.x - startPoint.x
            let dy = now.y - startPoint.y
            let minW = 275 * pixelScale
            let minH = 116 * pixelScale
            let newW = max(minW, startFrame.width + dx)
            let newH = max(minH, startFrame.height - dy)
            let newFrame = NSRect(x: startFrame.minX, y: startFrame.maxY - newH, width: newW, height: newH)
            window.setFrame(newFrame, display: true)
            needsDisplay = true
            return
        }
        guard pressed == .scrollbar else { return }
        let p = winampPoint(event)
        let extra = max(0, controller.playlist.count - listRows)
        controller.playlistScroll = Int(((p.y - 20).clamped(0, listRect.height) / max(1, listRect.height)) * CGFloat(extra))
    }

    override func mouseUp(with event: NSEvent) {
        let r = pressed
        let p = winampPoint(event)
        pressed = nil
        if r == .resize {
            resizeStartFrame = nil
            resizeStartScreenPoint = nil
        }
        defer { needsDisplay = true }
        switch r {
        case .close:
            controller.playlistWindow?.orderOut(nil); controller.playlistVisible = false
        case .add: controller.openPlaylistPanel()
        case .remove: if let selected { controller.removePlaylistItem(at: selected); self.selected = nil }
        case .misc: controller.clearPlaylist()
        case .select: selected = controller.currentPlaylistIndex
        case .list:
            let row = Int((p.y - listRect.minY) / 10)
            let idx = controller.playlistScroll + row
            if controller.playlist.indices.contains(idx) { selected = idx; if event.clickCount >= 2 { controller.playPlaylistItem(at: idx) } }
        case .scrollbar:
            let extra = max(0, controller.playlist.count - listRows)
            controller.playlistScroll = Int(((p.y - 20).clamped(0, listRect.height) / max(1, listRect.height)) * CGFloat(extra))
        case .resize:
            break
        default: break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let rows = listRows
        controller.playlistScroll = (controller.playlistScroll + (event.scrollingDeltaY > 0 ? -1 : 1)).clamped(0, max(0, controller.playlist.count - rows))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        controller.addToPlaylist(urls: urls, autoplayFirstIfEmpty: true)
        return !urls.isEmpty
    }

    private func hit(_ p: CGPoint) -> Region {
        let w = classicSize.width
        let h = classicSize.height
        if rect(w - 11, 3, 9, 9).contains(p) { return .close }
        if rect(w - 16, 20, 9, h - 58).contains(p) { return .scrollbar }
        if rect(w - 40, h - 38, 40, 38).contains(p) { return .resize }
        if listRect.contains(p) { return .list }
        let by = h - 28
        if rect(11, by, 40, 14).contains(p) { return .add }
        if rect(52, by, 40, 14).contains(p) { return .remove }
        if rect(94, by, 40, 14).contains(p) { return .select }
        if rect(136, by, 40, 14).contains(p) { return .misc }
        return .drag
    }

    private func formatTime(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
    private func winampPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / pixelScale, y: p.y / pixelScale)
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
}
