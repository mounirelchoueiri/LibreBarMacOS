import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var glucose: GlucoseManager

    private let height: CGFloat = 18
    private let foregroundColor = Color.white

    private var isOffline: Bool {
        if case .offline = glucose.connectionStatus { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 4) {
            if let reading = glucose.latestReading {
                if glucose.showColorDot {
                    Circle()
                        .fill(reading.color(low: glucose.lowThreshold, high: glucose.highThreshold))
                        .frame(width: 6, height: 6)
                }

                Text("\(reading.displayFormatted(mgdl: glucose.useMgdl)) \(reading.trendArrow)")
                    .font(.system(size: NSFont.systemFontSize, weight: .regular).monospacedDigit())
                    .foregroundStyle(foregroundColor)

                if glucose.showSparkline && glucose.history.count >= 2 {
                    Sparkline(values: glucose.history.suffix(24).map { $0.value })
                        .stroke(foregroundColor, lineWidth: 1)
                        .frame(width: 34, height: height - 6)
                }

                if isOffline {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(foregroundColor.opacity(0.7))
                }
            } else {
                Text("--")
                    .font(.system(size: NSFont.systemFontSize, weight: .regular).monospacedDigit())
                    .foregroundStyle(foregroundColor)
            }
        }
        .frame(height: height)
        .padding(.horizontal, 2)
    }
}

private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2 else { return path }

        let minV = (values.min() ?? 0) - 0.3
        let maxV = (values.max() ?? 10) + 0.3
        let range = maxV - minV
        guard range > 0 else { return path }

        let points: [CGPoint] = values.enumerated().map { i, v in
            let x = rect.minX + (CGFloat(i) / CGFloat(values.count - 1)) * rect.width
            // Flip Y so higher glucose is higher on screen
            let y = rect.maxY - CGFloat((v - minV) / range) * rect.height
            return CGPoint(x: x, y: y)
        }

        path.move(to: points[0])
        for pt in points.dropFirst() {
            path.addLine(to: pt)
        }
        return path
    }
}
