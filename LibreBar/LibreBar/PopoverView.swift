import SwiftUI

struct PopoverView: View {
    @ObservedObject var glucose: GlucoseManager
    @AppStorage("graph_hours") private var graphHours = 3
    @State private var copiedFlash = false

    private var offlineSince: Date? {
        if case .offline(let since) = glucose.connectionStatus { return since }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if let reading = glucose.latestReading {
                    content(reading: reading)
                } else if let error = glucose.errorMessage {
                    errorState(error)
                } else {
                    loadingState
                }
            }
            .padding(Theme.popoverPadding)

            Divider()
            actionBar
                .padding(.horizontal, Theme.popoverPadding)
                .padding(.vertical, 10)
                .background(.bar)
        }
        .frame(width: Theme.popoverWidth)
        .background(.regularMaterial)
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(reading: GlucoseReading) -> some View {
        if let since = offlineSince {
            offlineBanner(since: since)
        }

        if reading.isStale {
            staleBanner(reading)
        }

        Card {
            heroReading(reading)
        }
        .opacity(offlineSince == nil ? 1.0 : 0.75)

        if let rate = glucose.rateOfChange {
            predictions(reading: reading, rate: rate)
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("GRAPH")
                Spacer()
                rangePicker
                    .frame(width: 160)
            }

            Card(padding: 10) {
                GraphView(
                    readings: glucose.history,
                    hours: graphHours,
                    lowThreshold: glucose.lowThreshold,
                    highThreshold: glucose.highThreshold,
                    useMgdl: glucose.useMgdl,
                    rateOfChange: glucose.showPredictionLine ? glucose.rateOfChange : nil,
                    showMinMax: glucose.showMinMax
                )
            }
        }

        Card(padding: 10) {
            StatsView(
                history: glucose.history,
                graphHours: graphHours,
                lowThreshold: glucose.lowThreshold,
                highThreshold: glucose.highThreshold,
                useMgdl: glucose.useMgdl
            )
        }

        if let analysis = glucose.analysis {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(analysis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)
        }
    }

    private func heroReading(_ reading: GlucoseReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(reading.displayFormatted(mgdl: glucose.useMgdl))
                    .font(.system(size: Theme.heroValueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(reading.color(low: glucose.lowThreshold, high: glucose.highThreshold))

                Text(reading.trendArrow)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(reading.color(low: glucose.lowThreshold, high: glucose.highThreshold))

                Text(GlucoseReading.displayUnit(mgdl: glucose.useMgdl))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                if let rate = glucose.rateOfChange {
                    let displayRate = glucose.useMgdl ? rate * 18.0182 : rate
                    Text("\(displayRate >= 0 ? "+" : "")\(displayRate, specifier: glucose.useMgdl ? "%.1f" : "%.2f")/min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                copyButton(reading)
            }

            HStack(spacing: 6) {
                StatusPill(
                    reading.minutesAgo == 0 ? "Just now" : "\(reading.minutesAgo) min ago",
                    systemImage: "clock",
                    tint: reading.isStale ? .orange : .secondary
                )

                if let remaining = glucose.sensorRemainingText,
                   let expiration = glucose.sensorExpirationDate,
                   !glucose.isNightscout {
                    StatusPill(
                        remaining,
                        systemImage: "sensor.tag.radiowaves.forward",
                        tint: expiration.timeIntervalSinceNow <= 24 * 60 * 60 ? .orange : .secondary
                    )
                    .help("Sensor expires \(expiration.formatted(date: .long, time: .shortened))")
                }
            }
        }
    }

    private func predictions(reading: GlucoseReading, rate: Double) -> some View {
        let current = reading.value
        let pred30 = current + rate * 30
        let pred60 = current + rate * 60
        let fmt30 = glucose.useMgdl ? String(format: "%.0f", pred30 * 18.0182) : String(format: "%.1f", pred30)
        let fmt60 = glucose.useMgdl ? String(format: "%.0f", pred60 * 18.0182) : String(format: "%.1f", pred60)
        let unit = GlucoseReading.displayUnit(mgdl: glucose.useMgdl)
        let low = glucose.lowThreshold
        let high = glucose.highThreshold

        return HStack(spacing: 8) {
            predictionPill("30m", "\(fmt30) \(unit)", value: pred30, low: low, high: high)
            predictionPill("60m", "\(fmt60) \(unit)", value: pred60, low: low, high: high)
        }
    }

    private func predictionPill(_ label: String, _ value: String, value predicted: Double, low: Double, high: Double) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(predictionColor(predicted, low: low, high: high))
                .frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.12), in: Capsule())
    }

    private var rangePicker: some View {
        Picker("", selection: $graphHours) {
            Text("1h").tag(1)
            Text("3h").tag(3)
            Text("12h").tag(12)
            if glucose.isNightscout {
                Text("24h").tag(24)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: glucose.dataSource) { _, newValue in
            if newValue != "nightscout" && graphHours == 24 {
                graphHours = 12
            }
        }
    }

    private func copyButton(_ reading: GlucoseReading) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(reading.clipboardString(mgdl: glucose.useMgdl), forType: .string)
            copiedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copiedFlash = false
            }
        } label: {
            Image(systemName: copiedFlash ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12))
                .foregroundStyle(copiedFlash ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy current reading")
    }

    private func offlineBanner(since: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text("Offline since \(since.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .background(Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private func staleBanner(_ reading: GlucoseReading) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Data is stale — last update \(reading.minutesAgo) min ago")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading glucose data…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings to connect") {
                SettingsWindowController.shared.show(glucose: glucose)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var actionBar: some View {
        HStack {
            actionButton("Refresh", "arrow.clockwise") {
                Task { await glucose.fetchGlucose() }
            }
            Spacer()
            actionButton("Export", "square.and.arrow.up") {
                GlucoseExporter.presentSavePanel(
                    readings: glucose.history,
                    hours: graphHours,
                    source: glucose.isNightscout ? "Nightscout" : "LibreLinkUp"
                )
            }
            .disabled(glucose.history.isEmpty)
            Spacer()
            actionButton("Settings", "gearshape") {
                SettingsWindowController.shared.show(glucose: glucose)
            }
            Spacer()
            actionButton("Quit", "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func actionButton(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func predictionColor(_ value: Double, low: Double, high: Double) -> Color {
        if value < low - 0.8 { return .red }
        if value < low { return .orange }
        if value > high + 3.9 { return .red }
        if value > high { return .orange }
        return .green
    }
}
