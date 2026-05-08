import SwiftUI
import Charts

struct GraphView: View {
    let readings: [GlucoseReading]
    var hours: Int = 3
    var lowThreshold: Double = 3.9
    var highThreshold: Double = 10.0
    var useMgdl: Bool = false

    private var filtered: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return readings.filter { $0.timestamp > cutoff }
    }

    private func displayVal(_ mmol: Double) -> Double {
        useMgdl ? mmol * 18.0182 : mmol
    }

    var body: some View {
        if filtered.count >= 2 {
            Chart {
                RectangleMark(
                    yStart: .value("Low", displayVal(lowThreshold)),
                    yEnd: .value("High", displayVal(highThreshold))
                )
                .foregroundStyle(.green.opacity(0.08))

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
                plot.background(.quaternary.opacity(0.3))
            }
            .frame(height: 120)
        } else {
            Text("Not enough data for graph")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(height: 60)
        }
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
        let values = filtered.map { $0.displayValue(mgdl: useMgdl) }
        let lowD = displayVal(lowThreshold)
        let highD = displayVal(highThreshold)
        let pad: Double = useMgdl ? 10 : 0.5
        let minVal = min((values.min() ?? lowD) - pad, lowD - pad)
        let maxVal = max((values.max() ?? highD) + pad, highD + pad)
        return minVal...maxVal
    }
}
