import SwiftUI
import Combine

@main
struct LibreBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var glucose: GlucoseManager!
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeychainHelper.migrateIfNeeded()
        glucose = GlucoseManager()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateLabel()

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(glucose: glucose))

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        glucose.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateLabel() }
            }
            .store(in: &cancellables)

        HotkeyManager.shared.onTrigger = { [weak self] in
            DispatchQueue.main.async { self?.togglePopover() }
        }
        HotkeyManager.shared.register()
    }

    func updateLabel() {
        guard let button = statusItem.button else { return }
        guard let reading = glucose.latestReading else {
            button.image = nil
            button.title = "--"
            return
        }

        let text = "\(reading.displayFormatted(mgdl: glucose.useMgdl)) \(reading.trendArrow)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let showDot = glucose.showColorDot
        let showSpark = glucose.showSparkline && glucose.history.count >= 2

        if !showDot && !showSpark {
            button.image = nil
            button.title = text
            button.font = font
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let dotSize: CGFloat = 6
        let dotPad: CGFloat = showDot ? 4 : 0
        let dotWidth: CGFloat = showDot ? dotSize + dotPad : 0
        let sparkWidth: CGFloat = showSpark ? 36 : 0
        let sparkPad: CGFloat = showSpark ? 4 : 0
        let totalWidth = dotWidth + textSize.width + sparkPad + sparkWidth
        let height: CGFloat = max(18, textSize.height)

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            var x: CGFloat = 0

            if showDot {
                let color = reading.color(low: self.glucose.lowThreshold, high: self.glucose.highThreshold)
                let nsColor = NSColor(color)
                nsColor.setFill()
                let dotRect = NSRect(x: 0, y: (height - dotSize) / 2, width: dotSize, height: dotSize)
                NSBezierPath(ovalIn: dotRect).fill()
                x += dotWidth
            }

            let textRect = NSRect(x: x, y: (height - textSize.height) / 2, width: textSize.width, height: textSize.height)
            (text as NSString).draw(in: textRect, withAttributes: attrs)
            x += textSize.width + sparkPad

            if showSpark {
                self.drawSparkline(in: NSRect(x: x, y: 2, width: sparkWidth, height: height - 4))
            }

            return true
        }
        image.isTemplate = false

        button.title = ""
        button.image = image
    }

    private func drawSparkline(in rect: NSRect) {
        let readings = glucose.history.suffix(24)
        guard readings.count >= 2 else { return }

        let values = readings.map { $0.value }
        let minV = (values.min() ?? 0) - 0.3
        let maxV = (values.max() ?? 10) + 0.3
        let range = maxV - minV
        guard range > 0 else { return }

        let path = NSBezierPath()
        let points: [NSPoint] = values.enumerated().map { i, v in
            let x = rect.minX + (CGFloat(i) / CGFloat(values.count - 1)) * rect.width
            let y = rect.minY + CGFloat((v - minV) / range) * rect.height
            return NSPoint(x: x, y: y)
        }

        path.move(to: points[0])
        for pt in points.dropFirst() {
            path.line(to: pt)
        }

        NSColor.white.setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuBarPopover: View {
    @ObservedObject var glucose: GlucoseManager
    @AppStorage("graph_hours") private var graphHours = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reading = glucose.latestReading {
                HStack {
                    Text("\(reading.displayFormatted(mgdl: glucose.useMgdl)) \(GlucoseReading.displayUnit(mgdl: glucose.useMgdl))")
                        .font(.title2.bold())
                        .foregroundColor(reading.color(low: glucose.lowThreshold, high: glucose.highThreshold))

                    Text(reading.trendArrow)
                        .font(.title2)

                    Spacer()

                    if let rate = glucose.rateOfChange {
                        let displayRate = glucose.useMgdl ? rate * 18.0182 : rate
                        Text("\(displayRate >= 0 ? "+" : "")\(displayRate, specifier: glucose.useMgdl ? "%.1f" : "%.2f")/min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    let mins = reading.minutesAgo
                    if reading.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    Text(mins == 0 ? "Just now" : "\(mins) min ago")
                        .font(.caption)
                        .foregroundStyle(reading.isStale ? .orange : .secondary)

                    Spacer()

                    if let days = glucose.sensorDaysRemaining, !glucose.isNightscout {
                        HStack(spacing: 3) {
                            Image(systemName: "sensor.tag.radiowaves.forward")
                                .font(.caption2)
                            Text(days == 0 ? "Expiring today" : "\(days)d left")
                        }
                        .font(.caption)
                        .foregroundStyle(days <= 1 ? .orange : .secondary)
                    }
                }

                if let rate = glucose.rateOfChange {
                    let current = reading.value
                    let pred30 = current + rate * 30
                    let pred60 = current + rate * 60
                    let fmt30 = glucose.useMgdl ? String(format: "%.0f", pred30 * 18.0182) : String(format: "%.1f", pred30)
                    let fmt60 = glucose.useMgdl ? String(format: "%.0f", pred60 * 18.0182) : String(format: "%.1f", pred60)
                    let unit = GlucoseReading.displayUnit(mgdl: glucose.useMgdl)
                    let low = glucose.lowThreshold
                    let high = glucose.highThreshold
                    let time30 = Date().addingTimeInterval(30 * 60)
                    let time60 = Date().addingTimeInterval(60 * 60)
                    HStack(spacing: 12) {
                        predictionLabel("30m: \(fmt30) \(unit)", time: time30, value: pred30, low: low, high: high)
                        predictionLabel("60m: \(fmt60) \(unit)", time: time60, value: pred60, low: low, high: high)
                    }
                    .font(.caption2)
                }

                Picker("", selection: $graphHours) {
                    Text("1h").tag(1)
                    Text("3h").tag(3)
                    Text("12h").tag(12)
                    if glucose.isNightscout {
                        Text("24h").tag(24)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: glucose.dataSource) { _, newValue in
                    if newValue != "nightscout" && graphHours == 24 {
                        graphHours = 12
                    }
                }

                GraphView(readings: glucose.history, hours: graphHours, lowThreshold: glucose.lowThreshold, highThreshold: glucose.highThreshold, useMgdl: glucose.useMgdl, rateOfChange: glucose.showPredictionLine ? glucose.rateOfChange : nil, showMinMax: glucose.showMinMax)
                    .padding(.top, 2)

                StatsView(history: glucose.history, graphHours: graphHours, lowThreshold: glucose.lowThreshold, highThreshold: glucose.highThreshold, useMgdl: glucose.useMgdl)

                if let analysis = glucose.analysis {
                    Text(analysis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            } else if let error = glucose.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                Text("Loading...")
            }

            Divider()

            HStack {
                Button("Refresh") { Task { await glucose.fetchGlucose() } }
                Spacer()
                Button("Settings...") {
                    SettingsWindowController.shared.show(glucose: glucose)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(12)
        .frame(width: 280)
    }

    private func predictionLabel(_ text: String, time: Date, value: Double, low: Double, high: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(predictionColor(value, low: low, high: high))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .foregroundStyle(.secondary)
                Text("(\(time, format: .dateTime.hour().minute()))")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func predictionColor(_ value: Double, low: Double, high: Double) -> Color {
        if value < low - 0.8 { return .red }
        if value < low { return .orange }
        if value > high + 3.9 { return .red }
        if value > high { return .orange }
        return .green
    }
}

class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(glucose: GlucoseManager) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(glucose: glucose)
        let hostingView = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingView)
        window.title = "LibreBar Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
