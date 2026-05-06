import SwiftUI

struct StatsView: View {
    let history: [GlucoseReading]
    let graphHours: Int
    let lowThreshold: Double
    let highThreshold: Double
    let useMgdl: Bool

    private var filtered: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(graphHours) * 3600)
        return history.filter { $0.timestamp > cutoff }
    }

    private var timeInRangeLabel: String? {
        guard history.count >= 2,
              let first = history.first, let last = history.last else { return nil }
        let totalSpanSeconds = last.timestamp.timeIntervalSince(first.timestamp)
        guard totalSpanSeconds > 0 else { return nil }
        let inRangeCount = history.filter { $0.value >= lowThreshold && $0.value <= highThreshold }.count
        let fraction = Double(inRangeCount) / Double(history.count)
        let inRangeSeconds = totalSpanSeconds * fraction
        let inRangeHours = inRangeSeconds / 3600

        if inRangeHours >= 24 {
            let days = inRangeHours / 24
            return String(format: "%.1fd", days)
        } else {
            return String(format: "%.1fh", inRangeHours)
        }
    }

    private var periodInRange: Int? {
        guard !filtered.isEmpty else { return nil }
        let inRange = filtered.filter { $0.value >= lowThreshold && $0.value <= highThreshold }
        return Int(Double(inRange.count) / Double(filtered.count) * 100)
    }

    private var averageGlucose: Double? {
        guard !filtered.isEmpty else { return nil }
        let sum = filtered.reduce(0.0) { $0 + $1.value }
        return sum / Double(filtered.count)
    }

    var body: some View {
        if !history.isEmpty {
            HStack(spacing: 0) {
                statBox(
                    title: "Time in Range",
                    value: timeInRangeLabel ?? "--",
                    color: .green
                )

                Divider().frame(height: 36)

                statBox(
                    title: "Avg (\(graphHours)h)",
                    value: averageFormatted,
                    color: avgColor
                )

                Divider().frame(height: 36)

                statBox(
                    title: "In Range (\(graphHours)h)",
                    value: periodInRange.map { "\($0)%" } ?? "--",
                    color: tirColor(periodInRange)
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var averageFormatted: String {
        guard let avg = averageGlucose else { return "--" }
        if useMgdl {
            return String(format: "%.0f", avg * 18.0182)
        }
        return String(format: "%.1f", avg)
    }

    private var avgColor: Color {
        guard let avg = averageGlucose else { return .secondary }
        if avg >= lowThreshold && avg <= highThreshold { return .green }
        return .orange
    }

    private func tirColor(_ percent: Int?) -> Color {
        guard let p = percent else { return .secondary }
        if p >= 70 { return .green }
        if p >= 50 { return .orange }
        return .red
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
