import Foundation
import AppKit
import UniformTypeIdentifiers

enum GlucoseExporter {
    static func csv(from readings: [GlucoseReading], source: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")

        var lines = ["timestamp,glucose_mmol,glucose_mgdl,trend,source"]
        for r in readings.sorted(by: { $0.timestamp < $1.timestamp }) {
            let ts = iso.string(from: r.timestamp)
            let mmol = String(format: "%.1f", r.value)
            let mgdl = String(format: "%.0f", r.value * 18.0182)
            let trend = r.trendArrow.isEmpty ? "" : r.trendArrow
            lines.append("\(ts),\(mmol),\(mgdl),\(trend),\(source)")
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func presentSavePanel(readings: [GlucoseReading], hours: Int, source: String) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let filtered = readings.filter { $0.timestamp > cutoff }
        let content = csv(from: filtered, source: source)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let defaultName = "librebar-export-\(dateFormatter.string(from: Date()))-\(hours)h.csv"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
