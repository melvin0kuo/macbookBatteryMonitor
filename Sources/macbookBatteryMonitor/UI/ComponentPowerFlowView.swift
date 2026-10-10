import SwiftUI

struct ComponentPowerFlowView: View {
    let breakdown: PowerBreakdown
    let ui: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var chip: Bool { ui.powerFlowLevel == .chip }
    private var rows: [ComponentRow] {
        chip ? [
            ComponentRow(name: "CPU", symbol: "cpu", watts: breakdown.cpuWatts),
            ComponentRow(name: "GPU", symbol: "square.stack.3d.up", watts: breakdown.gpuWatts),
            ComponentRow(name: "ANE", symbol: "brain", watts: breakdown.aneWatts),
        ] : [
            ComponentRow(name: "螢幕背光", symbol: "display", watts: breakdown.backlightWatts),
            ComponentRow(name: "晶片運算", symbol: "cpu", watts: breakdown.chipWatts),
            ComponentRow(name: "其他（估算）", symbol: "ellipsis", watts: breakdown.otherWatts),
        ]
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                VStack(spacing: 5) {
                    Image(systemName: chip ? "cpu" : "laptopcomputer").font(.system(size: 21))
                    Text(Format.watts(chip ? breakdown.chipWatts : breakdown.systemWatts))
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    Text(chip ? (breakdown.cpuWatts != nil && breakdown.gpuWatts != nil && breakdown.aneWatts != nil ? "晶片合計" : "已取得合計") : "系統負載").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(width: 58, height: 92)
                .background(Color.primary.opacity(0.055), in: UnevenRoundedRectangle(topLeadingRadius: 13, bottomLeadingRadius: 13))
                ComponentRibbons(values: rows.map(\.watts), total: chip ? breakdown.chipWatts : breakdown.systemWatts,
                                 animated: !reduceMotion, dark: scheme == .dark)
                    .frame(maxWidth: .infinity).frame(height: 126)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if !chip && index == 1 {
                            Button { ui.powerFlowLevel = .chip } label: {
                                endpoint(row, expandable: true)
                            }
                            .buttonStyle(.plain)
                            .help("展開 CPU、GPU 與 ANE 功耗")
                            .accessibilityLabel("晶片運算，\(Format.watts(row.watts))，展開細項")
                        } else {
                            endpoint(row, expandable: false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(row.name)，\(Format.watts(row.watts))")
                        }
                    }
                }
                .frame(width: 72)
            }
            Text(breakdown.message)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("背光來自 SMC 感測器；CPU、GPU、ANE 來自系統能量模型估算。晶片合計不是完整 SoC 電源軌功耗。")
        }
    }

    private func endpoint(_ row: ComponentRow, expandable: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: row.symbol).font(.system(size: 14))
            HStack(spacing: 2) {
                Text(row.name).font(.system(size: 9))
                if expandable { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)) }
            }
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(Color.primary.opacity(expandable ? 0.085 : 0.055),
                    in: UnevenRoundedRectangle(bottomTrailingRadius: 11, topTrailingRadius: 11))
    }
}

private struct ComponentRow {
    var name: String
    var symbol: String
    var watts: Double?
}

private struct ComponentRibbons: NSViewRepresentable {
    let values: [Double?]
    let total: Double?
    let animated: Bool
    let dark: Bool
    func makeNSView(context: Context) -> ComponentRibbonView { ComponentRibbonView() }
    func updateNSView(_ view: ComponentRibbonView, context: Context) {
        let config = ComponentRibbonView.Configuration(values: values, total: total, animated: animated, dark: dark)
        if view.configuration != config { view.configuration = config; view.needsLayout = true }
    }
}

private final class ComponentRibbonView: NSView {
    struct Configuration: Equatable {
        var values: [Double?]
        var total: Double?
        var animated: Bool
        var dark: Bool
    }
    var configuration: Configuration?
    private let flows = PowerFlowLayers()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard let layer, let c = configuration, bounds.width > 8 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.filter { !(($0.name ?? "").hasPrefix("flow-")) }.forEach { $0.removeFromSuperlayer() }
        flows.begin(in: layer)
        let widths = c.values.map { watts -> CGFloat in
            guard let watts, watts.isFinite, watts > 0 else { return 0 }
            return max(3, min(28, CGFloat(watts / max(0.1, c.total ?? watts)) * 60))
        }
        var source = (bounds.height - widths.reduce(0, +)) / 2
        let start: CGFloat = 4
        let end = bounds.width - 4
        let ink = c.dark ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.24, alpha: 1)
        for index in c.values.indices {
            let center = CGFloat(index) * 44 + 19
            let width = widths[index]
            if width > 0 {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: start, y: source))
                path.addCurve(to: CGPoint(x: end, y: center - width / 2),
                              control1: CGPoint(x: bounds.width / 2, y: source),
                              control2: CGPoint(x: bounds.width / 2, y: center - width / 2))
                path.addLine(to: CGPoint(x: end, y: center + width / 2))
                path.addCurve(to: CGPoint(x: start, y: source + width),
                              control1: CGPoint(x: bounds.width / 2, y: center + width / 2),
                              control2: CGPoint(x: bounds.width / 2, y: source + width))
                path.closeSubpath()
                let base = CAShapeLayer()
                base.path = path
                base.fillColor = (c.dark ? NSColor.white : NSColor.black).withAlphaComponent(0.065).cgColor
                layer.addSublayer(base)
                flows.update(id: "flow-\(index)", path: path, bounds: bounds, animated: c.animated,
                             dark: c.dark, startX: start, endX: end)
                source += width
            }
            let label = CATextLayer()
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.frame = CGRect(x: 4, y: center - 8, width: bounds.width - 8, height: 20)
            label.alignmentMode = .center
            label.string = NSAttributedString(string: Format.watts(c.values[index]), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: ink])
            layer.addSublayer(label)
        }
        flows.end()
        CATransaction.commit()
    }
}
