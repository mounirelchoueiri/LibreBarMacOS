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

    func checkForUpdates(silent: Bool = true) {
        Task {
            await check(silent: silent)
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

    private func downloadAndInstall(dmgURL: URL) async {
        isUpdating = true

        let progressAlert = NSAlert()
        progressAlert.messageText = "Updating LibreBar..."
        progressAlert.informativeText = "Downloading update. Please wait."
        progressAlert.alertStyle = .informational
        progressAlert.addButton(withTitle: "Cancel")

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        indicator.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        progressAlert.accessoryView = indicator

        // Show non-modally so we can dismiss it
        let window = NSWindow()
        window.contentView = progressAlert.window.contentView

        do {
            // Download DMG
            let (tempURL, response) = try await URLSession.shared.download(from: dmgURL)
            let dmgPath = NSTemporaryDirectory() + "LibreBar-update.dmg"
            let dmgFileURL = URL(fileURLWithPath: dmgPath)
            try? FileManager.default.removeItem(at: dmgFileURL)
            try FileManager.default.moveItem(at: tempURL, to: dmgFileURL)

            // Verify we got an actual DMG file
            let attrs = try FileManager.default.attributesOfItem(atPath: dmgPath)
            let fileSize = attrs[.size] as? Int64 ?? 0
            let httpResponse = response as? HTTPURLResponse
            print("[LibreBar] Downloaded DMG: \(fileSize) bytes, HTTP \(httpResponse?.statusCode ?? 0)")
            guard fileSize > 1000 else {
                throw UpdateError.downloadFailed
            }

            // Mount DMG
            let mountPoint = try await mountDMG(at: dmgPath)

            // Find .app in mounted volume
            let appSource = mountPoint + "/LibreBar.app"
            guard FileManager.default.fileExists(atPath: appSource) else {
                throw UpdateError.appNotFound
            }

            // Get current app path
            let currentAppPath = Bundle.main.bundlePath

            // Replace app
            let backupPath = currentAppPath + ".bak"
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.moveItem(atPath: currentAppPath, toPath: backupPath)

            do {
                try FileManager.default.copyItem(atPath: appSource, toPath: currentAppPath)
            } catch {
                // Restore backup if copy fails
                try? FileManager.default.moveItem(atPath: backupPath, toPath: currentAppPath)
                throw error
            }

            // Clean up backup
            try? FileManager.default.removeItem(atPath: backupPath)

            // Unmount DMG
            await unmountDMG(mountPoint: mountPoint)
            try? FileManager.default.removeItem(at: dmgFileURL)

            // Relaunch
            relaunch()

        } catch {
            isUpdating = false
            let errorAlert = NSAlert()
            errorAlert.messageText = "Update Failed"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .critical
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
        }
    }

    private func mountDMG(at path: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path, "-nobrowse", "-plist"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read pipe data BEFORE waitUntilExit to avoid deadlock when buffer fills
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
