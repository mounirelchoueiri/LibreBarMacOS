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

    private var highCount: Int {
        filtered.filter { $0.value > highThreshold }.count
    }

    private var lowCount: Int {
        filtered.filter { $0.value < lowThreshold }.count
    }

    var body: some View {
        if !history.isEmpty {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
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

                Divider()

                HStack(spacing: 0) {
                    statBox(
                        title: "Highs (\(graphHours)h)",
                        value: "\(highCount)",
                        color: highCount > 0 ? .orange : .green
                    )

                    Divider().frame(height: 36)

                    statBox(
                        title: "Lows (\(graphHours)h)",
                        value: "\(lowCount)",
                        color: lowCount > 0 ? .red : .green
                    )
                }
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
