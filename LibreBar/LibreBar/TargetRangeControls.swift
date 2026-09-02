import SwiftUI

struct TargetRangeControls: View {
    @Binding var low: Double
    @Binding var high: Double
    let useMgdl: Bool

    var body: some View {
        VStack(spacing: 0) {
            RangeVisualizerBar(low: low, high: high, useMgdl: useMgdl)
                .padding(.horizontal, 18)
                .padding(.top, 30)
                .padding(.bottom, 14)

            rangeSliderRow(
                label: "Low",
                color: .orange,
                value: $low,
                range: 2.5...(high - 0.2),
                step: 0.1
            )

            rangeSliderRow(
                label: "High",
                color: .red,
                value: $high,
                range: (low + 0.2)...16.0,
                step: 0.1
            )
        }
    }

    private func formatRangeValue(_ value: Double) -> String {
        useMgdl ? "\(Int(round(value * 18.0182)))" : String(format: "%.1f", value)
    }

    private func rangeSliderRow(label: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 13))
            }
            .frame(width: 50, alignment: .leading)

            Slider(value: value, in: range, step: step)

            Text(formatRangeValue(value.wrappedValue))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .overlay(alignment: .top) { Divider() }
    }
}
