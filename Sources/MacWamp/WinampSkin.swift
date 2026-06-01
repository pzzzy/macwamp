import AppKit

struct SpriteSheet {
    let image: NSImage
    private let cgImage: CGImage
    private let pixelSize: CGSize

    init(_ name: String) {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "WinampClassic")
            ?? Bundle.module.url(forResource: name, withExtension: nil)
        if let url,
           let img = NSImage(contentsOf: url),
           let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data),
           let cg = rep.cgImage {
            img.isTemplate = false
            image = img
            cgImage = cg
            pixelSize = CGSize(width: cg.width, height: cg.height)
            return
        }

        let fallback = SpriteSheet.makeFallbackImage(for: name)
        image = fallback.image
        cgImage = fallback.cgImage
        pixelSize = CGSize(width: fallback.cgImage.width, height: fallback.cgImage.height)
    }

    private static func fallbackSize(for name: String) -> CGSize {
        switch name.lowercased() {
        case "main.bmp": return CGSize(width: 275, height: 116)
        case "cbuttons.bmp": return CGSize(width: 136, height: 36)
        case "titlebar.bmp": return CGSize(width: 344, height: 87)
        case "numbers.bmp": return CGSize(width: 99, height: 13)
        case "text.bmp": return CGSize(width: 155, height: 74)
        case "volume.bmp", "balance.bmp": return CGSize(width: 68, height: 433)
        case "posbar.bmp": return CGSize(width: 307, height: 10)
        case "playpaus.bmp": return CGSize(width: 42, height: 9)
        case "monoster.bmp": return CGSize(width: 58, height: 24)
        case "shufrep.bmp": return CGSize(width: 92, height: 85)
        case "pledit.bmp": return CGSize(width: 280, height: 186)
        case "eqmain.bmp": return CGSize(width: 275, height: 315)
        default: return CGSize(width: 275, height: 116)
        }
    }

    private static func makeFallbackImage(for name: String) -> (image: NSImage, cgImage: CGImage) {
        let size = fallbackSize(for: name)
        let width = Int(size.width)
        let height = Int(size.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: width,
                                  pixelsHigh: height,
                                  bitsPerSample: 8,
                                  samplesPerPixel: 4,
                                  hasAlpha: true,
                                  isPlanar: false,
                                  colorSpaceName: .deviceRGB,
                                  bytesPerRow: width * 4,
                                  bitsPerPixel: 32)!
        let data = rep.bitmapData!
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let checker = ((x / 8 + y / 8) % 2) == 0
                data[i + 0] = checker ? 46 : 35
                data[i + 1] = checker ? 43 : 34
                data[i + 2] = checker ? 65 : 54
                data[i + 3] = 255
            }
        }
        if name.lowercased() == "text.bmp" || name.lowercased() == "numbers.bmp" {
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                data[i + 0] = 64; data[i + 1] = 240; data[i + 2] = 64; data[i + 3] = 255
            }}
        }
        let cg = rep.cgImage!
        let image = NSImage(cgImage: cg, size: size)
        return (image, cg)
    }

    func draw(src: CGRect, dst: CGRect, alpha: CGFloat = 1) {
        // Winamp's BitBlt rectangles and NSBitmapImageRep/CGImage pixels are both
        // addressed here in displayed top-left image coordinates.  Do not flip Y:
        // flipping samples the bottom of TEXT/BALANCE/SHUFREP and causes the exact
        // gibberish text plus cut-off green buttons reported by the user.
        guard let cropped = cgImage.cropping(to: src.integral) else { return }
        let sprite = NSImage(cgImage: cropped, size: src.size)
        sprite.draw(in: dst.integral,
                    from: CGRect(origin: .zero, size: src.size),
                    operation: .sourceOver,
                    fraction: alpha,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.none])
    }
}

final class WinampSkin {
    let main = SpriteSheet("main.bmp")
    let titlebar = SpriteSheet("titlebar.bmp")
    let cbuttons = SpriteSheet("cbuttons.bmp")
    let numbers = SpriteSheet("numbers.bmp")
    let text = SpriteSheet("text.bmp")
    let volume = SpriteSheet("volume.bmp")
    let balance = SpriteSheet("balance.bmp")
    let posbar = SpriteSheet("posbar.bmp")
    let playpause = SpriteSheet("playpaus.bmp")
    let monoster = SpriteSheet("monoster.bmp")
    let shufrep = SpriteSheet("shufrep.bmp")
    let pledit = SpriteSheet("pledit.bmp")
    let eqmain = SpriteSheet("eqmain.bmp")

    static let width: CGFloat = 275
    static let height: CGFloat = 116

    func drawBase(active: Bool = true) {
        main.draw(src: CGRect(x: 0, y: 0, width: 275, height: 116), dst: CGRect(x: 0, y: 0, width: 275, height: 116))
        drawTitlebar(active: active)
    }

    func drawTitlebar(active: Bool) {
        let y = active ? 0 : 15
        titlebar.draw(src: CGRect(x: 27, y: y, width: 275, height: 14), dst: CGRect(x: 0, y: 0, width: 275, height: 14))
    }

    enum TitleButton { case minimize, shade, close }

    func drawTitleButtons(pressed: TitleButton? = nil) {
        // The titlebar strip already includes normal button artwork. Overlay only
        // pressed-state sprites; otherwise the old code copied cyan-backed sprites
        // over the strip and produced blue boxes.
        guard let pressed else { return }
        switch pressed {
        case .minimize:
            titlebar.draw(src: CGRect(x: 0, y: 9, width: 9, height: 9), dst: CGRect(x: 244, y: 3, width: 9, height: 9))
        case .shade:
            titlebar.draw(src: CGRect(x: 9, y: 9, width: 9, height: 9), dst: CGRect(x: 254, y: 3, width: 9, height: 9))
        case .close:
            titlebar.draw(src: CGRect(x: 18, y: 9, width: 9, height: 9), dst: CGRect(x: 264, y: 3, width: 9, height: 9))
        }
    }

    func drawTransport(pressed: Int?) {
        if let pressed {
            let d1 = [0, 23, 46, 69, 92]
            let d2 = [23, 46, 69, 92, 114]
            if pressed > 0 {
                cbuttons.draw(src: CGRect(x: 0, y: 0, width: d1[pressed], height: 18), dst: CGRect(x: 16, y: 88, width: d1[pressed], height: 18))
            }
            cbuttons.draw(src: CGRect(x: d1[pressed], y: 18, width: d2[pressed] - d1[pressed], height: 18), dst: CGRect(x: 16 + d1[pressed], y: 88, width: d2[pressed] - d1[pressed], height: 18))
            if pressed != 4 {
                cbuttons.draw(src: CGRect(x: d2[pressed], y: 0, width: 114 - d2[pressed], height: 18), dst: CGRect(x: 16 + d2[pressed], y: 88, width: 114 - d2[pressed], height: 18))
            }
        } else {
            cbuttons.draw(src: CGRect(x: 0, y: 0, width: 114, height: 18), dst: CGRect(x: 16, y: 88, width: 114, height: 18))
        }
    }

    func drawEject(pressed: Bool) {
        cbuttons.draw(src: CGRect(x: 114, y: pressed ? 18 : 0, width: 22, height: 16), dst: CGRect(x: 136, y: 89, width: 22, height: 16))
    }

    func drawPlayIcon(state: WinampController.State) {
        let offset: CGFloat
        switch state {
        case .playing: offset = 0
        case .paused: offset = 9
        case .stopped: offset = 18
        }
        playpause.draw(src: CGRect(x: offset, y: 0, width: 9, height: 9), dst: CGRect(x: 26, y: 28, width: 9, height: 9))
        playpause.draw(src: CGRect(x: state == .playing ? 36 : 27, y: 0, width: state == .playing ? 3 : 2, height: 9), dst: CGRect(x: 24, y: 28, width: state == .playing ? 3 : 2, height: 9))
    }

    func drawTime(seconds totalSeconds: Int) {
        let seconds = abs(totalSeconds % 60)
        let minutes = abs(totalSeconds / 60)
        numbers.draw(src: CGRect(x: 90, y: 0, width: 9, height: 13), dst: CGRect(x: 36, y: 26, width: 9, height: 13))
        if minutes / 100 > 0 { digit((minutes / 100) % 10, x: 36) }
        digit((minutes / 10) % 10, x: 48)
        digit(minutes % 10, x: 60)
        digit(seconds / 10, x: 78)
        digit(seconds % 10, x: 90)
    }

    private func digit(_ d: Int, x: CGFloat) {
        numbers.draw(src: CGRect(x: d * 9, y: 0, width: 9, height: 13), dst: CGRect(x: x, y: 26, width: 9, height: 13))
    }

    func drawBitrate(kbps: Int, khz: Int) {
        let b = min(max(kbps, 0), 999)
        drawFontCell(x: b >= 100 ? (b / 100) % 10 * 5 : 100, y: b >= 100 ? 6 : 12, dstX: 111, dstY: 43)
        drawFontCell(x: b >= 10 ? (b / 10) % 10 * 5 : 100, y: b >= 10 ? 6 : 12, dstX: 116, dstY: 43)
        drawFontCell(x: (b % 10) * 5, y: 6, dstX: 121, dstY: 43)
        let k = min(max(khz, 0), 99)
        drawFontCell(x: k >= 10 ? ((k / 10) % 10) * 5 : 100, y: k >= 10 ? 6 : 12, dstX: 156, dstY: 43)
        drawFontCell(x: (k % 10) * 5, y: 6, dstX: 161, dstY: 43)
    }

    func drawMonoStereo(value: Int) {
        monoster.draw(src: CGRect(x: 29, y: value == 1 ? 0 : 12, width: 28, height: 12), dst: CGRect(x: 212, y: 41, width: 28, height: 12))
        monoster.draw(src: CGRect(x: 0, y: value == 2 ? 0 : 12, width: 29, height: 12), dst: CGRect(x: 239, y: 41, width: 29, height: 12))
    }

    func drawPosition(position256: Int, pressed: Bool) {
        let position = CGFloat(position256.clamped(0, 256) * (248 - 29) / 256)
        if position > 0 {
            posbar.draw(src: CGRect(x: 0, y: 0, width: position, height: 10), dst: CGRect(x: 16, y: 72, width: position, height: 10))
        }
        posbar.draw(src: CGRect(x: pressed ? 278 : 248, y: 0, width: 29, height: 10), dst: CGRect(x: 16 + position, y: 72, width: 29, height: 10))
        if position < 219 {
            posbar.draw(src: CGRect(x: position + 29, y: 0, width: 219 - position, height: 10), dst: CGRect(x: 45 + position, y: 72, width: 219 - position, height: 10))
        }
    }

    func drawVolume(_ vol: Int, pressed: Bool) {
        let ypos = CGFloat((vol.clamped(0, 255) * 27 / 255) * 15)
        volume.draw(src: CGRect(x: 0, y: ypos, width: 68, height: 13), dst: CGRect(x: 107, y: 57, width: 68, height: 13))
        let xpos = CGFloat((vol.clamped(0, 255) * 51 / 255).clamped(0, 54))
        volume.draw(src: CGRect(x: pressed ? 0 : 15, y: 422, width: 14, height: 11), dst: CGRect(x: 107 + xpos, y: 58, width: 14, height: 11))
    }

    func drawBalance(_ pan: Int, pressed: Bool) {
        let p = pan.clamped(-127, 127)
        let ypos = CGFloat((abs(p) * 27 / 127) * 15)
        balance.draw(src: CGRect(x: 9, y: ypos, width: 38, height: 13), dst: CGRect(x: 177, y: 57, width: 38, height: 13))
        let xpos = CGFloat(((p * 12) / 127 + 12).clamped(0, 24))
        balance.draw(src: CGRect(x: pressed ? 0 : 15, y: 422, width: 14, height: 11), dst: CGRect(x: 177 + xpos, y: 58, width: 14, height: 11))
    }

    func drawShuffle(on: Bool, pressed: Bool) {
        shufrep.draw(src: CGRect(x: 28, y: (on ? 30 : 0) + (pressed ? 15 : 0), width: 47, height: 15), dst: CGRect(x: 164, y: 89, width: 47, height: 15))
    }

    func drawRepeat(on: Bool, pressed: Bool) {
        shufrep.draw(src: CGRect(x: 0, y: (on ? 30 : 0) + (pressed ? 15 : 0), width: 28, height: 15), dst: CGRect(x: 211, y: 89, width: 28, height: 15))
    }

    func drawEqPlaylist(eqOn: Bool, eqPressed: Bool, plOn: Bool, plPressed: Bool) {
        shufrep.draw(src: CGRect(x: eqPressed ? 46 : 0, y: (eqOn ? 12 : 0) + 61, width: 23, height: 12), dst: CGRect(x: 219, y: 58, width: 23, height: 12))
        shufrep.draw(src: CGRect(x: (plPressed ? 46 : 0) + 23, y: (plOn ? 12 : 0) + 61, width: 23, height: 12), dst: CGRect(x: 242, y: 58, width: 23, height: 12))
    }

    func drawAnalyzerFrame() {
        main.draw(src: CGRect(x: 24, y: 43, width: 76, height: 16), dst: CGRect(x: 24, y: 43, width: 76, height: 16))
    }

    func drawSongTitle(_ title: String, tick: Int) {
        let text = title.isEmpty ? "MACWAMP" : title.uppercased()
        let visibleWidth = 154
        let pixelLen = text.count * 5
        let spacer = "  ***  "
        let draw: String
        let start: Int
        if pixelLen > visibleWidth {
            draw = text + spacer + text
            start = (tick / 2) % max(1, text.count + spacer.count)
        } else {
            draw = text
            start = 0
        }
        main.draw(src: CGRect(x: 111, y: 27, width: 154, height: 6), dst: CGRect(x: 111, y: 27, width: 154, height: 6))
        var x = 111
        let chars = Array(draw.dropFirst(min(start, max(0, draw.count - 1))))
        for c in chars where x < 265 {
            drawTextChar(c, x: x, y: 27)
            x += 5
        }
        while x < 265 {
            drawTextChar("\u{0}", x: x, y: 27)
            x += 5
        }
    }

    private func drawTextChar(_ char: Character, x: Int, y: Int) {
        let c = xyForWinampFont(char)
        drawFontCell(x: c.0, y: c.1, dstX: x, dstY: y)
    }

    func drawFontCell(x: Int, y: Int, dstX: Int, dstY: Int) {
        text.draw(src: CGRect(x: x, y: y, width: 5, height: 6), dst: CGRect(x: dstX, y: dstY, width: 5, height: 6))
    }

    func xyForWinampFont(_ char: Character) -> (Int, Int) {
        if char == "\u{0}" { return (100, 12) }
        guard let scalar = String(char).unicodeScalars.first else { return (100, 12) }
        let v = scalar.value
        var column: UInt32
        var row = 0
        if v >= 65 && v <= 90 { column = v - 65 }
        else if v >= 97 && v <= 122 { column = v - 97 }
        else {
            row = 6
            switch char {
            case "\u{1}": column = 10
            case ".": column = 11
            case "0"..."9": column = v - 48
            case ":": column = 12
            case "(": column = 13
            case ")": column = 14
            case "-": column = 15
            case "'", "`": column = 16
            case "!": column = 17
            case "_": column = 18
            case "+": column = 19
            case "\\": column = 20
            case "/": column = 21
            case "[", "{", "<": column = 22
            case "]", "}", ">": column = 23
            case "~", "^": column = 24
            case "&": column = 25
            case "%": column = 26
            case ",": column = 27
            case "=": column = 28
            case "$": column = 29
            case "#": column = 30
            default:
                row = 0
                if char == "\"" { column = 26 }
                else if char == "@" { column = 27 }
                else { column = 30 }
            }
        }
        return (Int(column) * 5, row)
    }
}
