import Foundation
import AppKit

@MainActor
class UpdateChecker {
    static let shared = UpdateChecker()

    private let repo = "mounirelchoueiri/LibreBarMacOS"
    private let currentVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }()

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
                let htmlURL = json["html_url"] as? String ?? "https://github.com/\(repo)/releases/latest"
                showUpdateAlert(newVersion: latestVersion, notes: body, url: htmlURL)
            } else if !silent {
                showUpToDateAlert()
            }
        } catch {
            if !silent {
                print("[LibreBar] Update check failed: \(error)")
            }
        }
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

    private func showUpdateAlert(newVersion: String, notes: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "LibreBar \(newVersion) Available"
        alert.informativeText = "You are running v\(currentVersion). A new version is available.\n\n\(truncateNotes(notes))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
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
