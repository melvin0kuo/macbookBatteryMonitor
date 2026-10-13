import Foundation
import SwiftUI

enum ChargingVisualStyle: String, CaseIterable, Identifiable {
    case energy
    case mascot

    var id: String { rawValue }
    var title: String { self == .energy ? "電力流動" : "電池夥伴" }
}

enum ChargingJourneyTint: Equatable { case neutral, blue, green, orange }
enum BatteryMascotMood: Equatable { case resting, sleeping, charging, happy, worried }

struct ChargingJourneyPresentation: Equatable {
    var title: String
    var detail: String
    var progress: Double
    var tint: ChargingJourneyTint
    var mood: BatteryMascotMood
    var phase: ChargingPlanPhase?

    static func make(snapshot: BatterySnapshot, estimates: Estimates,
                     decision: ChargingPlanDecision?) -> ChargingJourneyPresentation {
        let progress = min(1, max(0, Double(snapshot.percent) / 100))
        guard let decision else {
            return ChargingJourneyPresentation(title: "智慧充電", detail: "設定完成時間",
                                                progress: progress, tint: .neutral,
                                                mood: .resting, phase: nil)
        }
        let deadline = decision.deadline.formatted(date: .omitted, time: .shortened)
        let start = decision.startAt?.formatted(date: .omitted, time: .shortened) ?? "稍後"
        switch decision.phase {
        case .unsupported:
            return .init(title: "充電旅程", detail: "這台 Mac 僅提供提醒，不會自動調整上限",
                         progress: progress, tint: .neutral, mood: .resting, phase: decision.phase)
        case .unplugged:
            return .init(title: "等待接上電源", detail: "目標 \(deadline) 完成",
                         progress: progress, tint: .neutral, mood: .resting, phase: decision.phase)
        case .waiting:
            return .init(title: "保養中 · 等待充電", detail: "預計 \(start) 開始，\(deadline) 完成",
                         progress: progress, tint: .blue, mood: .sleeping, phase: decision.phase)
        case .starting:
            return .init(title: "準備充電到 \(decision.targetPercent)%", detail: "目標 \(deadline) 完成",
                         progress: progress, tint: .blue, mood: .charging, phase: decision.phase)
        case .charging:
            return .init(title: "前往 \(decision.targetPercent)%", detail: "約 \(duration(decision.requiredMinutes))後完成",
                         progress: progress, tint: .green, mood: .charging, phase: decision.phase)
        case .systemPaused:
            return .init(title: "macOS 暫停充電", detail: "仍會以 \(deadline) 為目標持續追蹤",
                         progress: progress, tint: .orange, mood: .worried, phase: decision.phase)
        case .ready:
            return .init(title: "已準備好", detail: "已達 \(decision.targetPercent)% · 目標 \(deadline)",
                         progress: progress, tint: .green, mood: .happy, phase: decision.phase)
        case .late:
            return .init(title: "可能無法準時", detail: "持續充電中 · 原目標 \(deadline)",
                         progress: progress, tint: .orange, mood: .worried, phase: decision.phase)
        }
    }

    private static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) 分鐘" }
        let hours = minutes / 60, remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小時" : "\(hours) 小時 \(remainder) 分"
    }
}

struct ChargingJourneyView: View {
    let presentation: ChargingJourneyPresentation
    let style: ChargingVisualStyle
    let animated: Bool
    let openPlan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: openPlan) {
            HStack(spacing: 10) {
                if style == .mascot {
                    BatteryMascot(mood: presentation.mood, tint: tint)
                        .frame(width: 48, height: 38)
                } else {
                    energyTrack
                        .frame(width: 58, height: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.callout.weight(.semibold))
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("充電旅程，\(presentation.title)，\(presentation.detail)")
    }

    private var energyTrack: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animated || reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16)).frame(height: 8)
                Capsule().fill(tint.opacity(0.75))
                    .frame(width: max(8, 58 * presentation.progress), height: 8)
                if animated && !reduceMotion && presentation.phase == .charging {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .shadow(color: tint, radius: 5)
                        .offset(x: CGFloat(phase) * 50)
                }
                Image(systemName: presentation.phase == .ready ? "checkmark.circle.fill" : "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(y: -13)
            }
        }
    }

    private var tint: Color {
        switch presentation.tint {
        case .neutral: return .secondary
        case .blue: return .cyan
        case .green: return .green
        case .orange: return .orange
        }
    }
}

private struct BatteryMascot: View {
    let mood: BatteryMascotMood
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.65), lineWidth: 2))
            HStack(spacing: 8) {
                eye
                eye
            }
            .offset(y: -3)
            mouth
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 13, height: 7)
                .offset(y: 8)
        }
        .overlay(alignment: .trailing) {
            Capsule().fill(tint.opacity(0.7)).frame(width: 4, height: 13).offset(x: 4)
        }
    }

    private var eye: some View {
        Group {
            if mood == .sleeping {
                Capsule().fill(tint).frame(width: 7, height: 2)
            } else {
                Circle().fill(tint).frame(width: 4, height: 4)
            }
        }
    }

    private var mouth: Path {
        Path { path in
            switch mood {
            case .happy, .charging:
                path.move(to: .init(x: 1, y: 1)); path.addQuadCurve(to: .init(x: 12, y: 1), control: .init(x: 6.5, y: 8))
            case .worried:
                path.move(to: .init(x: 1, y: 6)); path.addQuadCurve(to: .init(x: 12, y: 6), control: .init(x: 6.5, y: 0))
            default:
                path.move(to: .init(x: 2, y: 4)); path.addLine(to: .init(x: 11, y: 4))
            }
        }
    }
}
