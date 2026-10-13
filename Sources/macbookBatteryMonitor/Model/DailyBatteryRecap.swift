import Foundation

struct DailyBatteryRecap: Equatable {
    var usedPercent: Int
    var chargedPercent: Int
    var plugInCount: Int
    var unpluggedMinutes: Int
    var longestUnpluggedMinutes: Int
    var startPercent: Int?
    var endPercent: Int?

    static func make(samples: [HistorySample], day: Date = Date(), calendar: Calendar = .current) -> DailyBatteryRecap {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return empty }
        let ordered = samples.sorted { $0.t < $1.t }
        let inside = ordered.filter { $0.t >= start && $0.t < end }
        guard !inside.isEmpty else { return empty }

        var points = inside
        if let previous = ordered.last(where: { $0.t < start }) {
            points.insert(HistorySample(t: start, pct: previous.pct, watts: previous.watts,
                                        plugged: previous.plugged, charging: previous.charging), at: 0)
        }

        var used = 0
        var charged = 0
        var plugs = 0
        var unpluggedSeconds: TimeInterval = 0
        var currentSession: TimeInterval = 0
        var longestSession: TimeInterval = 0

        var segmentPlugged = points[0].plugged
        var segmentStartPercent = points[0].pct
        var segmentEndPercent = points[0].pct

        func finishSegment() {
            let delta = segmentEndPercent - segmentStartPercent
            if segmentPlugged { charged += max(0, delta) }
            else { used += max(0, -delta) }
        }

        for (left, right) in zip(points, points.dropFirst()) {
            let rawInterval = max(0, right.t.timeIntervalSince(left.t))
            let knownInterval = min(rawInterval, 30 * 60)
            if !left.plugged {
                unpluggedSeconds += knownInterval
                currentSession += knownInterval
                longestSession = max(longestSession, currentSession)
            }
            if !left.plugged && right.plugged {
                plugs += 1
                currentSession = 0
                segmentEndPercent = left.pct
                finishSegment()
                segmentPlugged = true
                segmentStartPercent = right.pct
                segmentEndPercent = right.pct
            } else if left.plugged && !right.plugged {
                currentSession = 0
                segmentEndPercent = left.pct
                finishSegment()
                segmentPlugged = false
                segmentStartPercent = right.pct
                segmentEndPercent = right.pct
            }
            segmentEndPercent = right.pct
        }
        finishSegment()

        return DailyBatteryRecap(usedPercent: used, chargedPercent: charged, plugInCount: plugs,
                                 unpluggedMinutes: Int((unpluggedSeconds / 60).rounded()),
                                 longestUnpluggedMinutes: Int((longestSession / 60).rounded()),
                                 startPercent: points.first?.pct, endPercent: inside.last?.pct)
    }

    private static let empty = DailyBatteryRecap(usedPercent: 0, chargedPercent: 0, plugInCount: 0,
                                                  unpluggedMinutes: 0, longestUnpluggedMinutes: 0,
                                                  startPercent: nil, endPercent: nil)
}
