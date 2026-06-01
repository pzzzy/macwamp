import AppKit

final class WinampView: NSView {
    private let controller: WinampController
    private let skin = WinampSkin()
    private let pixelScale: CGFloat
    private var pressedRegion: Region?
    private var tick = 0
    private var displayTimer: Timer?

    private enum Region: Equatable {
        case prev, play, pause, stop, next, eject
        case position, volume, balance
        case shuffle, repeatOne, eq, playlist, close, minimize
        case drag
    }

    init(frame: NSRect, controller: WinampController, pixelScale: CGFloat) {
        self.controller = controller
        self.pixelScale = pixelScale
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        registerForDraggedTypes([.fileURL])
        controller.onChange = { [weak self] in self?.needsDisplay = true }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick += 1
                self?.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: pixelScale, y: pixelScale)

        skin.drawBase(active: window?.isKeyWindow ?? true)
        skin.drawTitleButtons(pressed: titleButton(pressedRegion))
        skin.drawTransport(pressed: transportIndex(pressedRegion))
        skin.drawEject(pressed: pressedRegion == .eject)
        skin.drawPlayIcon(state: controller.state)
        skin.drawTime(seconds: Int(controller.currentTime))
        skin.drawBitrate(kbps: controller.kbps, khz: controller.khz)
        skin.drawMonoStereo(value: controller.monoStereo)
        skin.drawPosition(position256: controller.progress256, pressed: pressedRegion == .position)
        skin.drawVolume(controller.volume, pressed: pressedRegion == .volume)
        skin.drawBalance(controller.balance, pressed: pressedRegion == .balance)
        skin.drawShuffle(on: controller.shuffle, pressed: pressedRegion == .shuffle)
        skin.drawRepeat(on: controller.repeatOne, pressed: pressedRegion == .repeatOne)
        skin.drawEqPlaylist(eqOn: controller.eqVisible, eqPressed: pressedRegion == .eq, plOn: controller.playlistVisible, plPressed: pressedRegion == .playlist)
        skin.drawSongTitle(controller.title, tick: tick)
        skin.drawAnalyzerFrame()
        drawAnalyzer(tick: tick)
        ctx.restoreGState()
    }

    private func drawAnalyzer(tick: Int) {
        let palette: [NSColor] = [
            NSColor(calibratedRed: 239/255, green: 49/255, blue: 16/255, alpha: 1),
            NSColor(calibratedRed: 206/255, green: 41/255, blue: 16/255, alpha: 1),
            NSColor(calibratedRed: 214/255, green: 90/255, blue: 0/255, alpha: 1),
            NSColor(calibratedRed: 214/255, green: 102/255, blue: 0/255, alpha: 1),
            NSColor(calibratedRed: 214/255, green: 115/255, blue: 0/255, alpha: 1),
            NSColor(calibratedRed: 198/255, green: 123/255, blue: 8/255, alpha: 1),
            NSColor(calibratedRed: 222/255, green: 165/255, blue: 24/255, alpha: 1),
            NSColor(calibratedRed: 214/255, green: 181/255, blue: 33/255, alpha: 1),
            NSColor(calibratedRed: 189/255, green: 222/255, blue: 41/255, alpha: 1),
            NSColor(calibratedRed: 148/255, green: 222/255, blue: 33/255, alpha: 1),
            NSColor(calibratedRed: 41/255, green: 206/255, blue: 16/255, alpha: 1),
            NSColor(calibratedRed: 50/255, green: 190/255, blue: 16/255, alpha: 1),
            NSColor(calibratedRed: 57/255, green: 181/255, blue: 16/255, alpha: 1),
            NSColor(calibratedRed: 49/255, green: 156/255, blue: 8/255, alpha: 1),
            NSColor(calibratedRed: 41/255, green: 148/255, blue: 0, alpha: 1),
        ]
        let energy = controller.state == .playing ? max(0.08, controller.analyzerLevel) : 0
        for band in 0..<19 {
            let x = 24 + band * 4
            let spectralShape = 1.0 - abs(Double(band) - 7.5) / 14.0
            let motion = (sin(Double(tick + band * 9) / 4.8) + sin(Double(tick * 2 + band * 13) / 11.0) + 2) / 4
            let normalized = (0.25 + spectralShape * 0.75) * (0.45 + motion * 0.55) * energy
            let height = controller.state == .playing ? Int((normalized * 17).clamped(1, 15)) : 0
            for col in 0..<3 {
                for y in stride(from: 0, to: height, by: 2) {
                    palette[(14 - y).clamped(0, palette.count - 1)].setFill()
                    NSRect(x: x + col, y: 43 + 15 - y, width: 1, height: 1).fill()
                }
            }
            if controller.state == .playing, height > 2 {
                NSColor(calibratedRed: 130/255, green: 214/255, blue: 33/255, alpha: 1).setFill()
                NSRect(x: x, y: 43 + max(0, 15 - height - 2), width: 3, height: 1).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = winampPoint(event)
        let region = hitTestWinamp(p)
        pressedRegion = region
        if region == .drag { window?.performDrag(with: event) }
        else { updateContinuous(region, point: p) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let region = pressedRegion else { return }
        updateContinuous(region, point: winampPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        let region = pressedRegion
        let point = winampPoint(event)
        pressedRegion = nil
        defer { needsDisplay = true }
        guard let region, hitTestWinamp(point) == region || region == .position || region == .volume || region == .balance else { return }
        switch region {
        case .prev: controller.previousTrack()
        case .play: controller.play()
        case .pause: controller.pause()
        case .stop: controller.stop()
        case .next: controller.nextTrack()
        case .eject: controller.openPanel()
        case .shuffle: controller.shuffle.toggle()
        case .repeatOne: controller.repeatOne.toggle()
        case .eq: controller.toggleEqualizerWindow()
        case .playlist: controller.togglePlaylistWindow()
        case .close: NSApp.terminate(nil)
        case .minimize: window?.miniaturize(nil)
        default: break
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ": controller.pause()
        case "o": controller.openPanel()
        case "x": controller.play()
        case "c": controller.pause()
        case "v": controller.stop()
        case "s": controller.shuffle.toggle()
        case "r": controller.repeatOne.toggle()
        case "e": controller.toggleEqualizerWindow()
        case "l": controller.togglePlaylistWindow()
        case "z": controller.previousTrack()
        case "b": controller.nextTrack()
        case "q": NSApp.terminate(nil)
        default: super.keyDown(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let item = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL else { return false }
        controller.load(url: item, autoplay: true)
        return true
    }

    private func updateContinuous(_ region: Region, point: CGPoint) {
        switch region {
        case .position:
            let x = (point.x - 16).clamped(0, 219)
            controller.seek(fraction: Double(x / 219))
        case .volume:
            let x = (point.x - 107).clamped(0, 51)
            controller.volume = Int(x / 51 * 255)
        case .balance:
            let x = (point.x - 177).clamped(0, 24)
            controller.balance = Int((x - 12) / 12 * 127)
        default: break
        }
        needsDisplay = true
    }

    private func winampPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / pixelScale, y: p.y / pixelScale)
    }

    private func hitTestWinamp(_ p: CGPoint) -> Region {
        if rect(264, 3, 9, 9).contains(p) { return .close }
        if rect(244, 3, 9, 9).contains(p) { return .minimize }
        if rect(16, 88, 23, 18).contains(p) { return .prev }
        if rect(39, 88, 23, 18).contains(p) { return .play }
        if rect(62, 88, 23, 18).contains(p) { return .pause }
        if rect(85, 88, 23, 18).contains(p) { return .stop }
        if rect(108, 88, 22, 18).contains(p) { return .next }
        if rect(136, 89, 22, 16).contains(p) { return .eject }
        if rect(16, 72, 248, 10).contains(p) { return .position }
        if rect(107, 57, 68, 13).contains(p) { return .volume }
        if rect(177, 57, 38, 13).contains(p) { return .balance }
        if rect(164, 89, 47, 15).contains(p) { return .shuffle }
        if rect(211, 89, 28, 15).contains(p) { return .repeatOne }
        if rect(219, 58, 23, 12).contains(p) { return .eq }
        if rect(242, 58, 23, 12).contains(p) { return .playlist }
        return .drag
    }

    private func transportIndex(_ region: Region?) -> Int? {
        switch region {
        case .prev: return 0
        case .play: return 1
        case .pause: return 2
        case .stop: return 3
        case .next: return 4
        default: return nil
        }
    }

    private func titleButton(_ region: Region?) -> WinampSkin.TitleButton? {
        switch region {
        case .close: return .close
        case .minimize: return .minimize
        default: return nil
        }
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
}
