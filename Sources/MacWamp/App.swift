import AppKit
import AVFoundation
import UniformTypeIdentifiers
import AudioToolbox

@main
final class MacWampApp: NSObject, NSApplicationDelegate {
    private var window: WinampWindow!
    private var controller: WinampController!

    static func main() {
        let app = NSApplication.shared
        let delegate = MacWampApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WinampController()
        window = WinampWindow(controller: controller)
        controller.mainWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        let args = Array(CommandLine.arguments.dropFirst())
        let inputURLs = args.filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
        if !inputURLs.isEmpty {
            controller.addToPlaylist(urls: inputURLs, autoplayFirstIfEmpty: true)
        }
        if args.contains("--show-eq") { controller.toggleEqualizerWindow() }
        if args.contains("--show-playlist") { controller.togglePlaylistWindow() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

final class WinampWindow: NSWindow {
    init(controller: WinampController) {
        let scale = CGFloat(2)
        let rect = NSRect(x: 0, y: 0, width: 275 * scale, height: 116 * scale)
        super.init(contentRect: rect,
                   styleMask: [.borderless, .miniaturizable],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        title = "MacWamp"
        let view = WinampView(frame: rect, controller: controller, pixelScale: scale)
        contentView = view
        minSize = rect.size
        maxSize = rect.size
        registerForDraggedTypes([.fileURL])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}


private final class AnalyzerBridge: @unchecked Sendable {
    weak var controller: WinampController?
    init(controller: WinampController) { self.controller = controller }
}

private func makeAnalyzerTapBlock(bridge: AnalyzerBridge) -> AVAudioNodeTapBlock {
    { buffer, _ in
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frameCount)
        for ch in 0..<max(1, channels) {
            let samples = UnsafeBufferPointer(start: channelData[ch], count: frameCount)
            for i in 0..<frameCount { mono[i] += samples[i] / Float(max(1, channels)) }
        }
        let sampleRate = buffer.format.sampleRate
        DispatchQueue.main.async { [weak bridge] in
            bridge?.controller?.updateAnalyzer(samples: mono, sampleRate: sampleRate)
        }
    }
}

@MainActor
final class WinampController: NSObject {
    enum State { case stopped, playing, paused }

    var state: State = .stopped { didSet { notifyChangeHandlers() } }
    var volume: Int = 205 { didSet { volume = volume.clamped(0, 255); playerNode.volume = Float(volume) / 255; notifyChangeHandlers() } }
    var balance: Int = 0 { didSet { balance = balance.clamped(-127, 127); playerNode.pan = Float(balance) / 127; notifyChangeHandlers() } }
    var shuffle = false { didSet { notifyChangeHandlers() } }
    var repeatOne = false { didSet { notifyChangeHandlers() } }
    var title = "MacWamp 0.1" { didSet { notifyChangeHandlers() } }
    var kbps = 0 { didSet { notifyChangeHandlers() } }
    var khz = 0 { didSet { notifyChangeHandlers() } }
    var monoStereo = 0 { didSet { notifyChangeHandlers() } }
    weak var mainWindow: NSWindow?
    var eqWindow: WinampAuxWindow?
    var playlistWindow: WinampAuxWindow?
    private var changeHandlers: [UUID: () -> Void] = [:]

    var eqVisible = false { didSet { notifyChangeHandlers() } }
    var playlistVisible = false { didSet { notifyChangeHandlers() } }
    var eqEnabled = false { didSet { applyEqualizer(); notifyChangeHandlers() } }
    var eqAuto = false { didSet { notifyChangeHandlers() } }
    var eqPreamp = 32 { didSet { eqPreamp = eqPreamp.clamped(0, 64); applyEqualizer(); notifyChangeHandlers() } }
    var eqBands: [Int] = Array(repeating: 32, count: 10) { didSet { eqBands = eqBands.map { $0.clamped(0, 64) }; applyEqualizer(); notifyChangeHandlers() } }
    var playlist: [PlaylistEntry] = [] { didSet { notifyChangeHandlers() } }
    var currentPlaylistIndex: Int? { didSet { notifyChangeHandlers() } }
    var playlistScroll = 0 { didSet { playlistScroll = playlistScroll.clamped(0, max(0, playlist.count - 1)); notifyChangeHandlers() } }

    var onChange: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eqUnit = AVAudioUnitEQ(numberOfBands: 10)
    private var analyzerBridge: AnalyzerBridge?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var playbackStartOffset: AVAudioFramePosition = 0
    private var pausedFrameOffset: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 44100
    private var playbackGeneration: UInt64 = 0
    private var timer: Timer?
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var analyzerLevel: Double = 0
    private(set) var analyzerBands: [Double] = Array(repeating: 0, count: 75)

    override init() {
        super.init()
        configureAudioEngine()
        startTimer()
    }

    @discardableResult
    func addChangeHandler(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        changeHandlers[id] = handler
        return id
    }

    func removeChangeHandler(_ id: UUID) { changeHandlers.removeValue(forKey: id) }

    func notifyChangeHandlers() {
        onChange?()
        changeHandlers.values.forEach { $0() }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.addToPlaylist(urls: [url], autoplayFirstIfEmpty: true)
        }
    }

    func openPlaylistPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.begin { [weak self] result in
            guard result == .OK else { return }
            self?.addToPlaylist(urls: panel.urls, autoplayFirstIfEmpty: true)
        }
    }

    func load(url: URL, autoplay: Bool) {
        do {
            let file = try AVAudioFile(forReading: url)
            playerNode.stop()
            audioFile = file
            currentURL = url
            audioSampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / max(1, audioSampleRate)
            playbackStartOffset = 0
            pausedFrameOffset = 0
            currentTime = 0
            schedulePlayback(from: 0)
            updateAudioInfo(for: url)
            let entry = playlistEntry(for: url)
            title = entry.title
            upsertPlaylistEntry(url: url, title: entry.title, duration: duration)
            if autoplay { play() } else { state = .stopped }
        } catch {
            NSSound.beep()
            title = "ERROR: \(url.lastPathComponent)"
            state = .stopped
        }
    }

    private func configureAudioEngine() {
        engine.attach(playerNode)
        engine.attach(eqUnit)
        engine.connect(playerNode, to: eqUnit, format: nil)
        engine.connect(eqUnit, to: engine.mainMixerNode, format: nil)
        installAnalyzerTap()
        playerNode.volume = Float(volume) / 255
        playerNode.pan = Float(balance) / 127
        let freqs: [Float] = [70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000]
        for (band, freq) in zip(eqUnit.bands, freqs) {
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.bypass = false
        }
        applyEqualizer()
    }

    private func applyEqualizer() {
        eqUnit.bypass = !eqEnabled
        eqUnit.globalGain = Float(eqPreamp - 32) / 32.0 * 12.0
        for (i, band) in eqUnit.bands.enumerated() where i < eqBands.count {
            band.gain = Float(eqBands[i] - 32) / 32.0 * 12.0
        }
    }

    private func installAnalyzerTap() {
        let bridge = AnalyzerBridge(controller: self)
        analyzerBridge = bridge
        let format = eqUnit.outputFormat(forBus: 0)
        eqUnit.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeAnalyzerTapBlock(bridge: bridge))
    }

    func updateAnalyzer(samples: [Float], sampleRate: Double) {
        guard state == .playing, !samples.isEmpty else { return }
        let n = min(samples.count, 1024)
        let minFreq = 60.0
        let maxFreq = min(16000.0, max(1000.0, sampleRate / 2.0 - 100.0))
        var newBands = [Double](repeating: 0, count: 75)
        for band in 0..<75 {
            let t = Double(band) / 74.0
            let freq = minFreq * pow(maxFreq / minFreq, t)
            let omega = 2.0 * Double.pi * freq / sampleRate
            var re = 0.0
            var im = 0.0
            var i = 0
            while i < n {
                let window = 0.5 - 0.5 * cos((2.0 * Double.pi * Double(i)) / Double(max(1, n - 1)))
                let s = Double(samples[i]) * window
                let phase = omega * Double(i)
                re += s * cos(phase)
                im -= s * sin(phase)
                i += 2
            }
            let mag = sqrt(re * re + im * im) / Double(max(1, n / 2))
            let db = 20.0 * log10(max(mag, 0.000001))
            let normalized = ((db + 58.0) / 44.0).clamped(0.0, 1.0)
            newBands[band] = pow(normalized, 0.72)
        }
        var smoothed = analyzerBands
        for i in 0..<75 { smoothed[i] = max(newBands[i], smoothed[i] * 0.68) }
        analyzerBands = smoothed
        analyzerLevel = (smoothed.reduce(0, +) / Double(smoothed.count)).clamped(0, 1)
        notifyChangeHandlers()
    }

    private func schedulePlayback(from offset: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        let safeOffset = offset.clamped(0, file.length)
        playbackStartOffset = safeOffset
        pausedFrameOffset = safeOffset
        let frames = AVAudioFrameCount(max(0, file.length - safeOffset))
        guard frames > 0 else { return }
        playbackGeneration &+= 1
        let generation = playbackGeneration
        playerNode.scheduleSegment(file, startingFrame: safeOffset, frameCount: frames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] callbackType in
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.playbackGeneration,
                      callbackType == .dataPlayedBack,
                      self.state == .playing else { return }
                self.currentTime = self.duration
                if self.repeatOne { self.seek(fraction: 0); self.play() }
                else { self.nextTrack() }
            }
        }
    }

    private func currentFrameOffset() -> AVAudioFramePosition {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return pausedFrameOffset }
        return playbackStartOffset + AVAudioFramePosition(playerTime.sampleTime)
    }

    private func updateAudioInfo(for url: URL) {
        var audioFileID: AudioFileID?
        if AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFileID) == noErr, let audioFileID {
            defer { AudioFileClose(audioFileID) }

            var dataFormat = AudioStreamBasicDescription()
            var dataFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &dataFormatSize, &dataFormat) == noErr {
                if dataFormat.mSampleRate.isFinite, dataFormat.mSampleRate > 0 {
                    khz = Int((dataFormat.mSampleRate / 1000).rounded())
                }
                if dataFormat.mChannelsPerFrame > 0 {
                    monoStereo = dataFormat.mChannelsPerFrame == 1 ? 1 : 2
                }
            }

            var bitRate: UInt32 = 0
            var bitRateSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioFileGetProperty(audioFileID, kAudioFilePropertyBitRate, &bitRateSize, &bitRate) == noErr, bitRate > 0 {
                kbps = Int((Double(bitRate) / 1000.0).rounded()).clamped(0, 999)
            } else {
                kbps = estimateBitrateFromAudioBytes(audioFile: audioFileID, duration: duration)
            }
        } else {
            if let file = self.audioFile {
                let sampleRate = file.processingFormat.sampleRate
                if sampleRate.isFinite, sampleRate > 0 { khz = Int((sampleRate / 1000).rounded()) }
                let channels = file.processingFormat.channelCount
                if channels > 0 { monoStereo = channels == 1 ? 1 : 2 }
            }
            kbps = estimateBitrateFromFileSize(url: url, duration: duration)
        }
    }

    private func estimateBitrateFromAudioBytes(audioFile: AudioFileID, duration: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        var byteCount: UInt64 = 0
        var byteCountSize = UInt32(MemoryLayout<UInt64>.size)
        if AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataByteCount, &byteCountSize, &byteCount) == noErr, byteCount > 0 {
            return Int(((Double(byteCount) * 8.0) / duration / 1000.0).rounded()).clamped(0, 999)
        }
        return 0
    }

    private func estimateBitrateFromFileSize(url: URL, duration: TimeInterval) -> Int {
        guard duration > 0,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize,
              bytes > 0 else {
            return 0
        }
        return Int(((Double(bytes) * 8.0) / duration / 1000.0).rounded()).clamped(0, 999)
    }

    func play() {
        guard audioFile != nil else { openPanel(); return }
        do {
            if !engine.isRunning { try engine.start() }
            playerNode.volume = Float(volume) / 255
            playerNode.pan = Float(balance) / 127
            playerNode.play()
            state = .playing
        } catch {
            NSSound.beep()
            state = .stopped
        }
    }

    func previousTrack() {
        guard !playlist.isEmpty else { return }
        let base = currentPlaylistIndex ?? 0
        let nextIndex = shuffle ? Int.random(in: 0..<playlist.count) : max(0, base - 1)
        playPlaylistItem(at: nextIndex)
    }

    func nextTrack() {
        guard !playlist.isEmpty else { return }
        let base = currentPlaylistIndex ?? -1
        let nextIndex: Int
        if shuffle { nextIndex = Int.random(in: 0..<playlist.count) }
        else if base + 1 < playlist.count { nextIndex = base + 1 }
        else if repeatOne { nextIndex = 0 }
        else { stop(); return }
        playPlaylistItem(at: nextIndex)
    }

    func addToPlaylist(urls: [URL], autoplayFirstIfEmpty: Bool) {
        let expanded = audioFileURLs(from: urls)
        guard !expanded.isEmpty else { NSSound.beep(); return }
        let wasEmpty = playlist.isEmpty
        for url in expanded where !playlist.contains(where: { $0.url == url }) {
            playlist.append(playlistEntry(for: url))
        }
        playlistScroll = playlistScroll.clamped(0, max(0, playlist.count - 1))
        if autoplayFirstIfEmpty, wasEmpty, let first = expanded.first { load(url: first, autoplay: true) }
    }

    private func audioFileURLs(from urls: [URL]) -> [URL] {
        var found: [URL] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        for url in urls {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if let enumerator = FileManager.default.enumerator(at: url,
                                                                   includingPropertiesForKeys: Array(keys),
                                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let child as URL in enumerator {
                        if isSupportedAudioFile(child) { found.append(child) }
                    }
                }
            } else if values?.isRegularFile == true || isSupportedAudioFile(url) {
                if isSupportedAudioFile(url) { found.append(url) }
            }
        }
        var seen = Set<String>()
        return found.map { $0.standardizedFileURL }.filter { seen.insert($0.path).inserted }
    }

    private func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp3", "m4a", "mp4", "aac", "wav", "aif", "aiff", "flac", "caf"].contains(ext)
    }

    private func playlistEntry(for url: URL) -> PlaylistEntry {
        var title = url.deletingPathExtension().lastPathComponent
        var duration: TimeInterval?

        if let file = try? AVAudioFile(forReading: url) {
            let sampleRate = file.processingFormat.sampleRate
            if sampleRate.isFinite, sampleRate > 0 {
                duration = Double(file.length) / sampleRate
            }
        }

        var audioFileID: AudioFileID?
        if AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFileID) == noErr, let audioFileID {
            defer { AudioFileClose(audioFileID) }
            var unmanagedInfo: Unmanaged<CFDictionary>?
            var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
            if AudioFileGetProperty(audioFileID, kAudioFilePropertyInfoDictionary, &size, &unmanagedInfo) == noErr,
               let info = unmanagedInfo?.takeRetainedValue() as? [String: Any] {
                let tagTitle = (info[kAFInfoDictionary_Title as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = (info[kAFInfoDictionary_Artist as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let tagTitle, !tagTitle.isEmpty {
                    if let artist, !artist.isEmpty, !tagTitle.localizedCaseInsensitiveContains(artist) {
                        title = "\(artist) - \(tagTitle)"
                    } else {
                        title = tagTitle
                    }
                }
            }
        }

        return PlaylistEntry(url: url, title: title, duration: duration)
    }

    private func upsertPlaylistEntry(url: URL, title: String, duration: TimeInterval) {
        if let existing = playlist.firstIndex(where: { $0.url == url }) {
            currentPlaylistIndex = existing
            playlist[existing].title = title
            playlist[existing].duration = duration
        } else {
            playlist.append(PlaylistEntry(url: url, title: title, duration: duration))
            currentPlaylistIndex = playlist.count - 1
        }
    }

    func playPlaylistItem(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        currentPlaylistIndex = index
        load(url: playlist[index].url, autoplay: true)
    }

    func removePlaylistItem(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        playlist.remove(at: index)
        if let currentPlaylistIndex { self.currentPlaylistIndex = playlist.isEmpty ? nil : min(currentPlaylistIndex, playlist.count - 1) }
        playlistScroll = min(playlistScroll, max(0, playlist.count - 1))
    }

    func clearPlaylist() {
        playlist.removeAll()
        currentPlaylistIndex = nil
        playlistScroll = 0
    }

    func resetEqualizer() {
        eqPreamp = 32
        eqBands = Array(repeating: 32, count: 10)
    }

    func setEqBand(_ index: Int, value: Int) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = value.clamped(0, 64)
        notifyChangeHandlers()
    }

    func toggleEqualizerWindow() {
        if eqVisible { eqWindow?.orderOut(nil); eqVisible = false; return }
        if eqWindow == nil {
            let scale = CGFloat(2)
            let rect = NSRect(x: 0, y: 0, width: 275 * scale, height: 116 * scale)
            eqWindow = WinampAuxWindow(contentRect: rect, title: "MacWamp Equalizer")
            eqWindow?.contentView = EqualizerView(frame: rect, controller: self, pixelScale: scale)
        }
        position(auxWindow: eqWindow, belowMainByClassicPixels: 116)
        eqWindow?.makeKeyAndOrderFront(nil)
        eqVisible = true
    }

    func togglePlaylistWindow() {
        if playlistVisible { playlistWindow?.orderOut(nil); playlistVisible = false; return }
        if playlistWindow == nil {
            let scale = CGFloat(2)
            let rect = NSRect(x: 0, y: 0, width: 375 * scale, height: 232 * scale)
            playlistWindow = WinampAuxWindow(contentRect: rect, title: "MacWamp Playlist", resizable: true)
            let view = PlaylistView(frame: rect, controller: self, pixelScale: scale)
            view.autoresizingMask = [.width, .height]
            playlistWindow?.contentView = view
            playlistWindow?.minSize = NSSize(width: 275 * scale, height: 116 * scale)
        }
        position(auxWindow: playlistWindow, belowMainByClassicPixels: eqVisible ? 232 : 116)
        playlistWindow?.makeKeyAndOrderFront(nil)
        playlistVisible = true
    }

    private func position(auxWindow: NSWindow?, belowMainByClassicPixels yOffset: CGFloat) {
        guard let mainWindow, let auxWindow else { return }
        let scale: CGFloat = 2
        let frame = mainWindow.frame
        auxWindow.setFrameOrigin(NSPoint(x: frame.minX, y: frame.maxY - (yOffset * scale) - auxWindow.frame.height))
    }

    func pause() {
        guard audioFile != nil else { return }
        if state == .playing {
            pausedFrameOffset = currentFrameOffset()
            playerNode.pause()
            state = .paused
        } else {
            if !playerNode.isPlaying { schedulePlayback(from: pausedFrameOffset) }
            play()
        }
    }

    func stop() {
        playerNode.stop()
        playbackStartOffset = 0
        pausedFrameOffset = 0
        if audioFile != nil { schedulePlayback(from: 0) }
        currentTime = 0
        analyzerLevel = 0
        analyzerBands = Array(repeating: 0, count: 75)
        state = .stopped
    }

    func seek(fraction: Double) {
        guard let file = audioFile, duration > 0 else { return }
        let offset = AVAudioFramePosition(Double(file.length) * fraction.clamped(0, 1))
        let wasPlaying = state == .playing
        playerNode.stop()
        schedulePlayback(from: offset)
        pausedFrameOffset = offset
        currentTime = Double(offset) / max(1, audioSampleRate)
        if wasPlaying { play() }
        notifyChangeHandlers()
    }

    var progress256: Int {
        guard duration > 0 else { return 0 }
        return Int((currentTime / duration) * 256).clamped(0, 256)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.audioFile != nil {
                    if self.state == .playing {
                        let frame = self.currentFrameOffset()
                        self.currentTime = (Double(frame) / max(1, self.audioSampleRate)).clamped(0, self.duration)
                        self.analyzerBands = self.analyzerBands.map { ($0 * 0.92).clamped(0, 1) }
                        self.analyzerLevel = (self.analyzerBands.reduce(0, +) / Double(max(1, self.analyzerBands.count))).clamped(0, 1)
                        if self.currentTime >= max(0, self.duration - 0.05), !self.playerNode.isPlaying {
                            self.nextTrack()
                        }
                    } else {
                        self.analyzerLevel *= 0.82
                    }
                }
                self.notifyChangeHandlers()
            }
        }
    }
}

struct PlaylistEntry: Equatable {
    let url: URL
    var title: String
    var duration: TimeInterval?
}

final class WinampAuxWindow: NSWindow {
    init(contentRect: NSRect, title: String, resizable: Bool = false) {
        var mask: NSWindow.StyleMask = [.borderless, .miniaturizable]
        if resizable { mask.insert(.resizable) }
        super.init(contentRect: contentRect,
                   styleMask: mask,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.title = title
        minSize = contentRect.size
        if !styleMask.contains(.resizable) { maxSize = contentRect.size }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}
