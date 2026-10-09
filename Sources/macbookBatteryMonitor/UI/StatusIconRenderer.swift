import AppKit

/// 畫選單列的電池圖示。用 drawingHandler 延後繪製，
/// labelColor 會在實際畫到選單列時才依深色/淺色外觀決定顏色。
enum StatusIconRenderer {
    static func image(percent: Int, state: PowerState, low: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 26, height: 13), flipped: false) { _ in
            let outlineColor = NSColor.labelColor.withAlphaComponent(0.5)
            let body = NSRect(x: 0.5, y: 0.5, width: 22.5, height: 12)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            outlineColor.setStroke()
            outline.stroke()
            outlineColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 23.75, y: 4, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()

            let inner = body.insetBy(dx: 2, dy: 2)
            let level = CGFloat(min(max(percent, 0), 100)) / 100
            let fill = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * level), height: inner.height)
            fillColor(state: state, low: low).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()

            if let name = overlaySymbol(state),
               let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
               let tinted = symbol.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: 8.5, weight: .black)
                       .applying(.init(paletteColors: [NSColor.labelColor]))
               ) {
                let s = tinted.size
                tinted.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
            }
            return true
        }
        image.accessibilityDescription = "電池 \(percent)%"
        return image
    }

    private static func fillColor(state: PowerState, low: Bool) -> NSColor {
        if low { return .systemRed }
        switch state {
        case .charging, .full, .pluggedIdle, .limitReached: return .systemGreen
        case .discharging: return NSColor.labelColor.withAlphaComponent(0.9)
        }
    }

    private static func overlaySymbol(_ state: PowerState) -> String? {
        switch state {
        case .charging: return "bolt.fill"
        case .pluggedIdle, .full, .limitReached: return "powerplug.fill"
        case .discharging: return nil
        }
    }
}
