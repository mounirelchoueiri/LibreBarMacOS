import SwiftUI

struct StatsView: View {
    let history: [GlucoseReading]
    let graphHours: Int
    let lowThreshold: Double
    let highThreshold: Double
    let useMgdl: Bool

    // Always 12h for TIR
    private var tir12h: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-12 * 3600)
        return history.filter { $0.timestamp > cutoff }
    }

    private var tirLowPct: Double {
        guard !tir12h.isEmpty else { return 0 }
        return Double(tir12h.filter { $0.value < lowThreshold }.count) / Double(tir12h.count)
    }

    private var tirInPct: Double {
        guard !tir12h.isEmpty else { return 0 }
        return Double(tir12h.filter { $0.value >= lowThreshold && $0.value <= highThreshold }.count) / Double(tir12h.count)
    }

    private var tirHighPct: Double {
        guard !tir12h.isEmpty else { return 0 }
        return Double(tir12h.filter { $0.value > highThreshold }.count) / Double(tir12h.count)
    }

    // Graph-period stats
    private var filtered: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(graphHours) * 3600)
        return history.filter { $0.timestamp > cutoff }
    }

    private var averageGlucose: Double? {
        guard !filtered.isEmpty else { return nil }
        return filtered.reduce(0.0) { $0 + $1.value } / Double(filtered.count)
    }

    private var highCount: Int { filtered.filter { $0.value > highThreshold }.count }
    private var lowCount: Int  { filtered.filter { $0.value < lowThreshold  }.count }

    private var gmiSummary: GMISummary? {
        GlucoseStats.gmi(from: history)
    }

    var body: some View {
        if !history.isEmpty {
            VStack(spacing: 8) {
                // TIR bar — always 12h
                if !tir12h.isEmpty {
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                if tirLowPct > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.red.opacity(0.85))
                                        .frame(width: geo.size.width * tirLowPct)
                                }
                                if tirInPct > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.green.opacity(0.85))
                                        .frame(width: geo.size.width * tirInPct)
                                }
                                if tirHighPct > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.opacity(0.85))
                                        .frame(width: geo.size.width * tirHighPct)
                                }
                            }
                        }
                        .frame(height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                        HStack(spacing: 0) {
                            tirLabel("Low", pct: tirLowPct, color: .red)
                            Spacer()
                            tirLabel("In Range", pct: tirInPct, color: .green)
                            Spacer()
                            tirLabel("High", pct: tirHighPct, color: .orange)
                        }

                        Text("Time in Range · 12h")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 2)
                }

                Divider()

                // Graph-period stats
                HStack(spacing: 0) {
                    statBox(
                        title: "Avg (\(graphHours)h)",
                        value: averageFormatted,
                        color: avgColor
                    )

                    Divider().frame(height: 36)

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

                if let gmi = gmiSummary {
                    Divider()

                    statBox(
                        title: gmi.windowLabel,
                        value: gmi.formatted,
                        color: .secondary
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tirLabel(_ label: String, pct: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(pct * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(pct > 0 ? color : .secondary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var averageFormatted: String {
        guard let avg = averageGlucose else { return "--" }
        return useMgdl
            ? String(format: "%.0f", avg * 18.0182)
            : String(format: "%.1f", avg)
    }

    private var avgColor: Color {
        guard let avg = averageGlucose else { return .secondary }
        return (avg >= lowThreshold && avg <= highThreshold) ? .green : .orange
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
