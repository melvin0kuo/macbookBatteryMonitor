import AppKit
import QuartzCore
final class AnimationTests {
    func testNumericUpdatesKeepAnimationPhase() {
        let parent = CALayer()
        let flows = PowerFlowLayers()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        flows.begin(in: parent)
        flows.update(id: "flow-0", path: CGPath(rect: bounds, transform: nil), bounds: bounds,
                     animated: true, dark: false, startX: 0, endX: 100)
        flows.end()
        let original = parent.sublayers!.first!
        let beam = original.sublayers!.first!
        let phase = beam.animation(forKey: "energyFlow")!.beginTime
        flows.begin(in: parent)
        flows.update(id: "flow-0", path: CGPath(rect: bounds.insetBy(dx: 2, dy: 2), transform: nil), bounds: bounds,
                     animated: true, dark: true, startX: 0, endX: 100)
        flows.end()
        XCTAssertTrue(parent.sublayers!.first! === original)
        XCTAssertEqual(beam.animation(forKey: "energyFlow")!.beginTime, phase)
        XCTAssertEqual(beam.animation(forKey: "energyFlow")!.duration, 3.6)
    }
    func testStoppedFlowsRemoveAnimationsAndObsoleteBranches() {
        let parent = CALayer()
        let flows = PowerFlowLayers()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        flows.begin(in: parent)
        flows.update(id: "flow-0", path: CGPath(rect: bounds, transform: nil), bounds: bounds,
                     animated: true, dark: false, startX: 0, endX: 100)
        flows.end()
        flows.begin(in: parent)
        flows.update(id: "flow-0", path: CGPath(rect: bounds, transform: nil), bounds: bounds,
                     animated: false, dark: false, startX: 0, endX: 100)
        flows.end()
        XCTAssertNil(parent.sublayers!.first!.sublayers!.first!.animation(forKey: "energyFlow"))
        flows.begin(in: parent)
        flows.end()
        XCTAssertTrue(parent.sublayers?.isEmpty ?? true)
    }
}
