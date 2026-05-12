import Foundation
import AppKit

@MainActor
class UpdateChecker {
    static let shared = UpdateChecker()

    private let repo = "mounirelchoueiri/LibreBarMacOS"
    private let currentVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }()

    @Published var isUpdating = false
    private var dailyTimer: Timer?
    private var progressWindow: NSWindow?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?

    func checkForUpdates(silent: Bool = true) {
        Task {
            await check(silent: silent)
        }
    }

    func scheduleDailyCheck() {
        dailyTimer?.invalidate()

        // Find next 9:00 AM
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        components.second = 0

        guard let next9am = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return }

        let interval = next9am.timeIntervalSinceNow
        dailyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates(silent: true)
                // Reschedule for tomorrow
                self?.scheduleDailyCheck()
            }
        }
    }

    private func check(silent: Bool) async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            if isNewer(latestVersion, than: currentVersion) {
                let body = json["body"] as? String ?? ""
                let dmgURL = findDMGAsset(in: json)
                showUpdateAlert(newVersion: latestVersion, notes: body, dmgURL: dmgURL)
            } else if !silent {
                showUpToDateAlert()
            }
        } catch {
            if !silent {
                print("[LibreBar] Update check failed: \(error)")
            }
        }
    }

    private func findDMGAsset(in release: [String: Any]) -> URL? {
        guard let assets = release["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
               let urlString = asset["browser_download_url"] as? String {
                return URL(string: urlString)
            }
        }
        return nil
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private func showUpdateAlert(newVersion: String, notes: String, dmgURL: URL?) {
        let alert = NSAlert()
        alert.messageText = "LibreBar \(newVersion) Available"
        alert.informativeText = "You are running v\(currentVersion). A new version is available.\n\n\(truncateNotes(notes))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let dmgURL {
                Task { await downloadAndInstall(dmgURL: dmgURL) }
            }
        }
    }

    // MARK: - Progress Window

    private func showProgressWindow() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Updating LibreBar"
        window.isReleasedWhenClosed = false
        window.level = .floating

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 120))

        let icon = NSImageView(frame: NSRect(x: 20, y: 48, width: 40, height: 40))
        if let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil) {
            icon.image = img
            icon.contentTintColor = .controlAccentColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        }
        container.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: "Downloading update...")
        titleLabel.frame = NSRect(x: 70, y: 72, width: 250, height: 20)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        container.addSubview(titleLabel)

        let bar = NSProgressIndicator(frame: NSRect(x: 70, y: 50, width: 245, height: 14))
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        container.addSubview(bar)

        let sublabel = NSTextField(labelWithString: "Starting...")
        sublabel.frame = NSRect(x: 70, y: 28, width: 250, height: 16)
        sublabel.font = .systemFont(ofSize: 11)
        sublabel.textColor = .secondaryLabelColor
        container.addSubview(sublabel)

        window.contentView = container
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.progressWindow = window
        self.progressBar = bar
        self.progressLabel = sublabel
    }

    private func updateProgress(_ fraction: Double, status: String) {
        progressBar?.doubleValue = fraction
        progressLabel?.stringValue = status
    }

    private func closeProgressWindow() {
        progressWindow?.close()
        progressWindow = nil
        progressBar = nil
        progressLabel = nil
    }

    // MARK: - Download & Install

    private func downloadAndInstall(dmgURL: URL) async {
        isUpdating = true
        showProgressWindow()

        do {
            // Download DMG with progress tracking
            updateProgress(0, status: "Connecting...")
            let delegate = DownloadProgressDelegate { [weak self] fraction in
                Task { @MainActor in
                    let pct = Int(fraction * 100)
                    self?.updateProgress(fraction * 0.7, status: "Downloading... \(pct)%")
                }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: dmgURL)
            session.invalidateAndCancel()

            updateProgress(0.7, status: "Download complete")

            let dmgPath = NSTemporaryDirectory() + "LibreBar-update.dmg"
            let dmgFileURL = URL(fileURLWithPath: dmgPath)
            try? FileManager.default.removeItem(at: dmgFileURL)
            try FileManager.default.moveItem(at: tempURL, to: dmgFileURL)

            // Verify download
            let attrs = try FileManager.default.attributesOfItem(atPath: dmgPath)
            let fileSize = attrs[.size] as? Int64 ?? 0
            let httpResponse = response as? HTTPURLResponse
            print("[LibreBar] Downloaded DMG: \(fileSize) bytes, HTTP \(httpResponse?.statusCode ?? 0)")
            guard fileSize > 1000 else {
                throw UpdateError.downloadFailed
            }

            // Mount DMG
            updateProgress(0.75, status: "Preparing update...")
            let mountPoint = try await mountDMG(at: dmgPath)

            // Find .app
            let appSource = mountPoint + "/LibreBar.app"
            guard FileManager.default.fileExists(atPath: appSource) else {
                throw UpdateError.appNotFound
            }

            // Replace app
            updateProgress(0.85, status: "Installing...")
            let currentAppPath = Bundle.main.bundlePath
            let backupPath = currentAppPath + ".bak"
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.moveItem(atPath: currentAppPath, toPath: backupPath)

            do {
                try FileManager.default.copyItem(atPath: appSource, toPath: currentAppPath)
            } catch {
                try? FileManager.default.moveItem(atPath: backupPath, toPath: currentAppPath)
                throw error
            }

            // Clean up
            try? FileManager.default.removeItem(atPath: backupPath)
            updateProgress(0.95, status: "Cleaning up...")
            await unmountDMG(mountPoint: mountPoint)
            try? FileManager.default.removeItem(at: dmgFileURL)

            // Done
            updateProgress(1.0, status: "Relaunching...")
            try? await Task.sleep(nanoseconds: 600_000_000)
            relaunch()

        } catch {
            isUpdating = false
            closeProgressWindow()
            let errorAlert = NSAlert()
            errorAlert.messageText = "Update Failed"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .critical
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
        }
    }

    // MARK: - DMG Handling

    private func mountDMG(at path: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path, "-nobrowse", "-plist"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("[LibreBar] hdiutil failed: \(errorMsg)")
            throw UpdateError.mountFailed
        }

        guard !data.isEmpty,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            print("[LibreBar] hdiutil plist parse failed, data size: \(data.count)")
            throw UpdateError.mountFailed
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }
        throw UpdateError.mountFailed
    }

    private func unmountDMG(mountPoint: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private func relaunch() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "LibreBar v\(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func truncateNotes(_ notes: String) -> String {
        let lines = notes.components(separatedBy: .newlines).prefix(8)
        let text = lines.joined(separator: "\n")
        return text.count > 300 ? String(text.prefix(300)) + "..." : text
    }
}

// MARK: - Download Progress Delegate

class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by async download call
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(fraction)
    }
}

// MARK: - Errors

enum UpdateError: Error, LocalizedError {
    case appNotFound
    case mountFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .appNotFound: return "Could not find LibreBar.app in the update package"
        case .mountFailed: return "Could not open the update package"
        case .downloadFailed: return "Downloaded file is not a valid update package"
        }
    }
}
