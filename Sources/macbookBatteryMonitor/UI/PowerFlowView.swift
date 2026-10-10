import SwiftUI

struct PowerFlowView: View {
    let s: BatterySnapshot
    let e: Estimates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PowerFlowDiagram(snapshot: s, estimates: e, animated: !reduceMotion, dark: colorScheme == .dark)
            .frame(height: 126)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("電力流向")
            .accessibilityValue("系統耗電 \(Format.watts(e.systemWatts))，電池\(e.batteryWatts >= 0.05 ? "充電" : "放電") \(Format.watts(abs(e.batteryWatts)))")
    }
}

private struct PowerFlowDiagram: NSViewRepresentable {
    let snapshot: BatterySnapshot
    let estimates: Estimates
    let animated: Bool
    let dark: Bool

    func makeNSView(context: Context) -> DiagramView { DiagramView() }
    func updateNSView(_ view: DiagramView, context: Context) {
        let configuration = DiagramView.Configuration(
            connected: snapshot.externalConnected, batteryWatts: estimates.batteryWatts,
            systemWatts: estimates.systemWatts, adapterWatts: estimates.adapterInputWatts,
            ratedWatts: snapshot.adapter?.watts, animated: animated, dark: dark)
        if view.configuration != configuration {
            view.configuration = configuration
            view.needsLayout = true
        }
    }
}

/// 灰色 Sankey 圖由 Core Animation 合成，標籤固定在流帶中央。
private final class DiagramView: NSView {
    struct Configuration: Equatable {
        var connected: Bool
        var batteryWatts: Double
        var systemWatts: Double?
        var adapterWatts: Double?
        var ratedWatts: Int?
        var animated: Bool
        var dark: Bool
    }
    var configuration: Configuration?
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard let layer, let c = configuration, bounds.width > 100 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let clipping = CAShapeLayer()
        clipping.path = CGPath(roundedRect: bounds, cornerWidth: 15, cornerHeight: 15, transform: nil)
        layer.mask = clipping
        let h = bounds.height
        let w = bounds.width
        let sourceWidth: CGFloat = 44
        let sinkX = w - 44
        let x1 = sourceWidth + 4
        let x2 = sinkX - 4
        let charging = c.batteryWatts >= 0.05
        let mixed = c.connected && c.batteryWatts <= -0.05
        let active = c.connected || abs(c.batteryWatts) >= 0.05
        let adapterText: String = c.adapterWatts.map { Format.watts($0) }
            ?? c.ratedWatts.map { "\($0) W*" } ?? "—"

        if charging {
            // 右上電池、右下系統，來源端的兩條流帶相接。
            let share = max(0.28, min(0.65, c.batteryWatts / max(0.1, c.batteryWatts + (c.systemWatts ?? 0))))
            let split = h * CGFloat(share)
            let sourceSplit = 12 + (h - 24) * CGFloat(share)
            node(CGRect(x: 0, y: 12, width: sourceWidth, height: h - 24),
                 symbol: "bolt.fill", value: adapterText, bolt: true)
            node(CGRect(x: sinkX, y: 0, width: 44, height: split - 4), symbol: "battery.100percent.bolt")
            node(CGRect(x: sinkX, y: split + 10, width: 44, height: h - split - 10), symbol: "laptopcomputer")
            ribbon(x1: x1, x2: x2, sourceTop: 12, sourceBottom: sourceSplit,
                   sinkTop: 0, sinkBottom: split - 4, value: Format.watts(c.batteryWatts), active: active)
            ribbon(x1: x1, x2: x2, sourceTop: sourceSplit, sourceBottom: h - 12,
                   sinkTop: split + 10, sinkBottom: h, value: Format.watts(c.systemWatts), active: active)
        } else if mixed {
            let split = h / 2
            node(CGRect(x: 0, y: 0, width: sourceWidth, height: split - 5),
                 symbol: "bolt.fill", value: adapterText, bolt: true)
            node(CGRect(x: 0, y: split + 5, width: sourceWidth, height: split - 5),
                 symbol: "battery.75percent", value: Format.watts(abs(c.batteryWatts)))
            node(CGRect(x: sinkX, y: 12, width: 44, height: h - 24), symbol: "laptopcomputer")
            let share = max(0.25, min(0.75, abs(c.batteryWatts) / max(0.1, c.systemWatts ?? 0)))
            let join = h - 12 - (h - 24) * CGFloat(share)
            ribbon(x1: x1, x2: x2, sourceTop: 0, sourceBottom: split - 5,
                   sinkTop: 12, sinkBottom: join, value: adapterText, active: true)
            ribbon(x1: x1, x2: x2, sourceTop: split + 5, sourceBottom: h,
                   sinkTop: join, sinkBottom: h - 12, value: Format.watts(abs(c.batteryWatts)), active: true)
        } else {
            let rect = CGRect(x: 0, y: 12, width: sourceWidth, height: h - 24)
            node(rect, symbol: c.connected ? "bolt.fill" : "battery.75percent",
                 value: c.connected ? adapterText : nil, bolt: c.connected)
            node(CGRect(x: sinkX, y: 12, width: 44, height: h - 24), symbol: "laptopcomputer")
            ribbon(x1: x1, x2: x2, sourceTop: 12, sourceBottom: h - 12,
                   sinkTop: 12, sinkBottom: h - 12, value: Format.watts(c.systemWatts), active: active)
        }
        CATransaction.commit()
    }

    private var surface: NSColor {
        configuration?.dark == true ? NSColor(white: 1, alpha: 0.065) : NSColor(white: 0, alpha: 0.055)
    }
    private var ink: NSColor {
        configuration?.dark == true ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.24, alpha: 1)
    }

    private func node(_ rect: CGRect, symbol: String, value: String? = nil, bolt: Bool = false) {
        let shape = CAShapeLayer()
        let outline = CGMutablePath()
        outline.addRoundedRect(in: rect, cornerWidth: 13, cornerHeight: 13)
        // 接流帶的一側為直角，外側保留大圓角。
        outline.addRect(CGRect(x: rect.minX == 0 ? rect.midX : rect.minX,
                               y: rect.minY, width: rect.width / 2, height: rect.height))
        shape.path = outline
        shape.fillColor = surface.cgColor
        layer?.addSublayer(shape)
        let iconSize: CGFloat = bolt ? 20 : 21
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: iconSize, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [bolt ? .systemYellow : ink]))
        if let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let icon = CALayer()
            icon.contents = cgImage
            icon.contentsGravity = .resizeAspect
            icon.frame = CGRect(x: rect.midX - 13, y: rect.midY - (value == nil ? 13 : 22), width: 26, height: 26)
            layer?.addSublayer(icon)
        }
        if let value {
            text(value, rect: CGRect(x: rect.minX + 1, y: rect.midY + 6, width: rect.width - 2, height: 18), size: 10.5, weight: .medium)
        }
    }

    private func ribbon(x1: CGFloat, x2: CGFloat, sourceTop: CGFloat, sourceBottom: CGFloat,
                        sinkTop: CGFloat, sinkBottom: CGFloat, value: String, active: Bool) {
        let path = CGMutablePath()
        let length = x2 - x1
        path.move(to: CGPoint(x: x1, y: sourceTop))
        path.addCurve(to: CGPoint(x: x2, y: sinkTop),
                      control1: CGPoint(x: x1 + length * 0.5, y: sourceTop),
                      control2: CGPoint(x: x2 - length * 0.5, y: sinkTop))
        path.addLine(to: CGPoint(x: x2, y: sinkBottom))
        path.addCurve(to: CGPoint(x: x1, y: sourceBottom),
                      control1: CGPoint(x: x2 - length * 0.5, y: sinkBottom),
                      control2: CGPoint(x: x1 + length * 0.5, y: sourceBottom))
        path.closeSubpath()
        let base = CAShapeLayer()
        base.path = path
        base.fillColor = surface.cgColor
        layer?.addSublayer(base)
        if active && configuration?.animated == true {
            let container = CALayer()
            container.frame = bounds
            let mask = CAShapeLayer()
            mask.path = path
            container.mask = mask
            layer?.addSublayer(container)
            for index in 0..<3 {
                let glow = CAGradientLayer()
                glow.bounds = CGRect(x: 0, y: 0, width: 36, height: bounds.height)
                let light = configuration?.dark == true ? NSColor.white : NSColor.black
                glow.colors = [light.withAlphaComponent(0).cgColor,
                               light.withAlphaComponent(0.055).cgColor,
                               light.withAlphaComponent(0).cgColor]
                glow.startPoint = CGPoint(x: 0, y: 0.5)
                glow.endPoint = CGPoint(x: 1, y: 0.5)
                glow.position = CGPoint(x: x1 + length * (CGFloat(index) + 0.5) / 3, y: bounds.height / 2)
                container.addSublayer(glow)
                let travel = CABasicAnimation(keyPath: "position.x")
                travel.fromValue = x1 - 18
                travel.toValue = x2 + 18
                travel.duration = 3.6
                travel.repeatCount = .infinity
                travel.beginTime = CACurrentMediaTime() - Double(index) * 1.2
                glow.add(travel, forKey: "energyFlow")
            }
        }
        let centerY = (sourceTop + sourceBottom + sinkTop + sinkBottom) / 4
        text(value, rect: CGRect(x: x1 + 4, y: centerY - 9, width: length - 8, height: 20), size: 12.5, weight: .semibold)
    }

    private func text(_ value: String, rect: CGRect, size: CGFloat, weight: NSFont.Weight) {
        let label = CATextLayer()
        label.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        label.frame = rect
        label.alignmentMode = .center
        label.string = NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: ink,
        ])
        layer?.addSublayer(label)
    }
}
