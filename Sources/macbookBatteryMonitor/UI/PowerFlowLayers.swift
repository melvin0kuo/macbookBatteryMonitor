import AppKit
import QuartzCore

/// 數值或曲線更新只修改 mask，既有動畫的 beginTime 保持不變。
final class PowerFlowLayers {
    private struct Entry {
        let layer: CALayer
        let mask: CAShapeLayer
        let beams: [CAGradientLayer]
    }
    private var entries: [String: Entry] = [:]
    private var seen = Set<String>()
    private weak var parent: CALayer?
    private let epoch = CACurrentMediaTime()

    func begin(in parent: CALayer) { self.parent = parent; seen.removeAll() }
    func update(id: String, path: CGPath, bounds: CGRect, animated: Bool, dark: Bool,
                startX: CGFloat, endX: CGFloat) {
        seen.insert(id)
        let entry: Entry
        if let existing = entries[id] {
            entry = existing
        } else {
            let root = CALayer()
            root.name = id
            let mask = CAShapeLayer()
            root.mask = mask
            let beams = (0..<3).map { _ -> CAGradientLayer in
                let beam = CAGradientLayer()
                root.addSublayer(beam)
                return beam
            }
            entry = Entry(layer: root, mask: mask, beams: beams)
            entries[id] = entry
            parent?.addSublayer(root)
        }
        entry.layer.frame = bounds
        entry.mask.path = path
        entry.layer.isHidden = !animated
        for (index, beam) in entry.beams.enumerated() {
            beam.bounds = CGRect(x: 0, y: 0, width: 36, height: bounds.height)
            let color = dark ? NSColor.white : NSColor.black
            beam.colors = [color.withAlphaComponent(0).cgColor,
                           color.withAlphaComponent(0.055).cgColor,
                           color.withAlphaComponent(0).cgColor]
            beam.startPoint = CGPoint(x: 0, y: 0.5)
            beam.endPoint = CGPoint(x: 1, y: 0.5)
            beam.position = CGPoint(x: startX + (endX - startX) * (CGFloat(index) + 0.5) / 3, y: bounds.height / 2)
            if animated && beam.animation(forKey: "energyFlow") == nil {
                let travel = CABasicAnimation(keyPath: "position.x")
                travel.fromValue = startX - 18
                travel.toValue = endX + 18
                travel.duration = 3.6
                travel.repeatCount = .infinity
                travel.beginTime = epoch - Double(index) * 1.2
                beam.add(travel, forKey: "energyFlow")
            } else if !animated {
                beam.removeAnimation(forKey: "energyFlow")
            }
        }
    }
    func end() {
        for key in Array(entries.keys) where !seen.contains(key) {
            entries.removeValue(forKey: key)?.layer.removeFromSuperlayer()
        }
    }
}
