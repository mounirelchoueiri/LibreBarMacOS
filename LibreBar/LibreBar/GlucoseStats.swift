import Foundation

struct GMISummary {
    let gmiPercent: Double
    let windowHours: Int
    let readingCount: Int

    var windowLabel: String {
        if windowHours >= 24 {
            let days = Int((Double(windowHours) / 24.0).rounded())
            return "GMI · \(days)d"
        }
        return "GMI · \(windowHours)h"
    }

    var formatted: String {
        String(format: "%.1f%%", gmiPercent)
    }
}

enum GlucoseStats {
    /// Estimated glucose management indicator using the ADA formula:
    /// GMI (%) = 3.31 + 0.02392 × mean glucose (mg/dL).
    /// Returns nil when the sample is too small to be meaningful.
    static func gmi(from readings: [GlucoseReading], maxAgeHours: Int = 14 * 24) -> GMISummary? {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeHours) * 3600)
        let window = readings.filter { $0.timestamp > cutoff }

        guard window.count >= 12,
              let first = window.first?.timestamp,
              let last = window.last?.timestamp else { return nil }

        let spanHours = last.timeIntervalSince(first) / 3600
        guard spanHours >= 3 else { return nil }

        let meanMmol = window.reduce(0.0) { $0 + $1.value } / Double(window.count)
        let meanMgdl = meanMmol * 18.0182
        let gmi = 3.31 + 0.02392 * meanMgdl

        return GMISummary(
            gmiPercent: gmi,
            windowHours: Int(spanHours.rounded()),
            readingCount: window.count
        )
    }
}
