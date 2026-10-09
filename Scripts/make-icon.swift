// 產生 App 圖示：swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS 圖示的圓角方形底
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(red: 0.13, green: 0.16, blue: 0.22, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: background, angle: -90)

    // 電池外框
    let bw = rect.width * 0.62, bh = rect.width * 0.32
    let body = NSRect(x: rect.midX - bw / 2 - rect.width * 0.03, y: rect.midY - bh / 2, width: bw, height: bh)
    let outline = NSBezierPath(roundedRect: body, xRadius: bh * 0.25, yRadius: bh * 0.25)
    outline.lineWidth = max(1, s * 0.022)
    NSColor(white: 1, alpha: 0.85).setStroke()
    outline.stroke()
    NSColor(white: 1, alpha: 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: body.maxX + s * 0.015, y: body.midY - bh * 0.18, width: s * 0.035, height: bh * 0.36),
                 xRadius: s * 0.012, yRadius: s * 0.012).fill()

    // 電量填色
    let pad = s * 0.035
    let fill = NSRect(x: body.minX + pad, y: body.minY + pad, width: (body.width - pad * 2) * 0.72, height: body.height - pad * 2)
    NSGradient(starting: NSColor(red: 0.30, green: 0.88, blue: 0.45, alpha: 1),
               ending: NSColor(red: 0.12, green: 0.70, blue: 0.35, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: fill, xRadius: bh * 0.12, yRadius: bh * 0.12), angle: -90)

    // 閃電
    if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: bh * 0.62, weight: .black).applying(.init(paletteColors: [.white]))) {
        let b = bolt.size
        bolt.draw(in: NSRect(x: body.midX - b.width / 2, y: body.midY - b.height / 2, width: b.width, height: b.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✅ \(output)" : "iconutil 失敗")
