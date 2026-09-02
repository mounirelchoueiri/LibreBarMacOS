import SwiftUI
import Charts

struct GraphView: View {
    let readings: [GlucoseReading]
    var hours: Int = 3
    var lowThreshold: Double = 3.9
    var highThreshold: Double = 10.0
    var useMgdl: Bool = false
    var rateOfChange: Double? = nil
    var showMinMax: Bool = true

    @State private var hoveredReading: GlucoseReading?

    private var filtered: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return readings.filter { $0.timestamp > cutoff }
    }

    private func displayVal(_ mmol: Double) -> Double {
        useMgdl ? mmol * 18.0182 : mmol
    }

    private var minReading: GlucoseReading? {
        filtered.min(by: { $0.value < $1.value })
    }

    private var maxReading: GlucoseReading? {
        filtered.max(by: { $0.value < $1.value })
    }

    private var predictionPoints: [(date: Date, value: Double)] {
        guard let rate = rateOfChange, let last = filtered.last else { return [] }
        let base = last.value
        let t0 = last.timestamp
        return stride(from: 5.0, through: 60.0, by: 5.0).map { mins in
            let predicted = base + rate * mins
            return (date: t0.addingTimeInterval(mins * 60), value: displayVal(predicted))
        }
    }

    var body: some View {
        if filtered.count >= 2 {
            Chart {
                // In-range band
                RectangleMark(
                    yStart: .value("Low", displayVal(lowThreshold)),
                    yEnd: .value("High", displayVal(highThreshold))
                )
                .foregroundStyle(.green.opacity(0.08))

                // Gradient fill under line
                ForEach(filtered) { reading in
                    let val = reading.displayValue(mgdl: useMgdl)
                    AreaMark(
                        x: .value("Time", reading.timestamp),
                        yStart: .value("Glucose", val),
                        yEnd: .value("Base", yDomain.lowerBound)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [gradientColor(for: reading).opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Main line
                ForEach(filtered) { reading in
                    let val = reading.displayValue(mgdl: useMgdl)
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", val)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", val)
                    )
                    .foregroundStyle(reading.color(low: lowThreshold, high: highThreshold))
                    .symbolSize(16)
                }

                // Prediction line (dotted)
                if let last = filtered.last {
                    let lastVal = last.displayValue(mgdl: useMgdl)
                    LineMark(
                        x: .value("Time", last.timestamp),
                        y: .value("Glucose", lastVal),
                        series: .value("Series", "prediction")
                    )
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.linear)

                    ForEach(Array(predictionPoints.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.value),
                            series: .value("Series", "prediction")
                        )
                        .foregroundStyle(.blue.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.linear)
                    }
                }

                // Min marker
                if showMinMax, let minR = minReading {
                    let val = minR.displayValue(mgdl: useMgdl)
                    PointMark(
                        x: .value("Time", minR.timestamp),
                        y: .value("Glucose", val)
                    )
                    .foregroundStyle(.red.opacity(0.8))
                    .symbolSize(30)
                    .annotation(position: .bottom, spacing: 2) {
                        Text(minR.displayFormatted(mgdl: useMgdl))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }

                // Max marker
                if showMinMax, let maxR = maxReading {
                    let val = maxR.displayValue(mgdl: useMgdl)
                    PointMark(
                        x: .value("Time", maxR.timestamp),
                        y: .value("Glucose", val)
                    )
                    .foregroundStyle(.orange.opacity(0.8))
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 2) {
                        Text(maxR.displayFormatted(mgdl: useMgdl))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }

                // Hover marker + tooltip
                if let hovered = hoveredReading {
                    let val = hovered.displayValue(mgdl: useMgdl)
                    RuleMark(x: .value("Time", hovered.timestamp))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("Time", hovered.timestamp),
                        y: .value("Glucose", val)
                    )
                    .foregroundStyle(hovered.color(low: lowThreshold, high: highThreshold))
                    .symbolSize(40)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(hovered.displayFormatted(mgdl: useMgdl)) \(GlucoseReading.displayUnit(mgdl: useMgdl))")
                                .font(.system(size: 10, weight: .semibold))
                            Text(hovered.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                        )
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: xCount)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .chartPlotStyle { plot in
                plot.background(.quaternary.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHover(at: location, proxy: proxy, geo: geo)
                            case .ended:
                                hoveredReading = nil
                            }
                        }
                }
            }
            .frame(height: 160)
            .clipped()
        } else {
            Text("Not enough data for graph")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(height: 60)
        }
    }

    private func updateHover(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let origin = geo[proxy.plotAreaFrame].origin
        let xPosition = location.x - origin.x
        guard let date: Date = proxy.value(atX: xPosition) else {
            hoveredReading = nil
            return
        }
        hoveredReading = filtered.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }

    private func gradientColor(for reading: GlucoseReading) -> Color {
        reading.color(low: lowThreshold, high: highThreshold)
    }

    private var xCount: Int {
        switch hours {
        case 1: return 1
        case 3: return 1
        case 24: return 6
        default: return 3
        }
    }

    private var yDomain: ClosedRange<Double> {
        var values = filtered.map { $0.displayValue(mgdl: useMgdl) }
        values.append(contentsOf: predictionPoints.map { $0.value })
        let lowD = displayVal(lowThreshold)
        let highD = displayVal(highThreshold)
        let pad: Double = useMgdl ? 10 : 0.5
        let minVal = min((values.min() ?? lowD) - pad, lowD - pad)
        let maxVal = max((values.max() ?? highD) + pad, highD + pad)
        return minVal...maxVal
    }
}
