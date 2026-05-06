import SwiftUI
import ServiceManagement

@main
struct LibreBarApp: App {
    @StateObject private var glucose = GlucoseManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(glucose: glucose)
        } label: {
            MenuBarLabel(glucose: glucose)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var glucose: GlucoseManager

    var body: some View {
        if let reading = glucose.latestReading {
            Text("\(reading.displayFormatted(mgdl: glucose.useMgdl)) \(reading.trendArrow)")
                .monospacedDigit()
        } else {
            Text("--")
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

                    if let days = glucose.sensorDaysRemaining {
                        HStack(spacing: 3) {
                            Image(systemName: "sensor.tag.radiowaves.forward")
                                .font(.caption2)
                            Text(days == 0 ? "Expiring today" : "\(days)d left")
                        }
                        .font(.caption)
                        .foregroundStyle(days <= 1 ? .orange : .secondary)
                    }
                }

                Picker("", selection: $graphHours) {
                    Text("1h").tag(1)
                    Text("3h").tag(3)
                    Text("12h").tag(12)
                }
                .pickerStyle(.segmented)

                GraphView(readings: glucose.history, hours: graphHours, lowThreshold: glucose.lowThreshold, highThreshold: glucose.highThreshold, useMgdl: glucose.useMgdl)
                    .padding(.top, 2)

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
