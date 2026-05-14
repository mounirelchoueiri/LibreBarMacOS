import Foundation
import SwiftUI
import CryptoKit

struct LibreConnection: Identifiable, Hashable {
    let id: String
    let firstName: String
    let lastName: String

    var displayName: String { "\(firstName) \(lastName)" }
}

struct GlucoseReading: Identifiable {
    let id = UUID()
    let value: Double
    let trendArrow: String
    let timestamp: Date
    let unit: String

    func color(low: Double = 3.9, high: Double = 10.0) -> Color {
        let urgentLow = low - 0.8
        let urgentHigh = high + 3.9
        switch value {
        case ..<urgentLow:    return .red
        case urgentLow..<low: return .orange
        case low...high:      return .green
        case high...urgentHigh: return .orange
        default:              return .red
        }
    }

    func displayValue(mgdl: Bool) -> Double {
        mgdl ? value * 18.0182 : value
    }

    func displayFormatted(mgdl: Bool) -> String {
        if mgdl {
            return String(format: "%.0f", value * 18.0182)
        } else {
            return String(format: "%.1f", value)
        }
    }

    static func displayUnit(mgdl: Bool) -> String {
        mgdl ? "mg/dL" : "mmol/L"
    }

    var minutesAgo: Int {
        Int(Date().timeIntervalSince(timestamp) / 60)
    }

    var isStale: Bool { minutesAgo > 15 }
}

@MainActor
class GlucoseManager: ObservableObject {
    @Published var latestReading: GlucoseReading?
    @Published var history: [GlucoseReading] = []
    @Published var rateOfChange: Double?
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var connections: [LibreConnection] = []
    @Published var sensorDaysRemaining: Int?

    @AppStorage("libre_email") var email = ""
    @AppStorage("libre_region") var region = "us"
    @AppStorage("threshold_low") var lowThreshold = 3.9
    @AppStorage("threshold_high") var highThreshold = 10.0
    @AppStorage("selected_connection_id") var selectedConnectionId = ""
    @AppStorage("use_mgdl") var useMgdl = false
    @AppStorage("data_source") var dataSource = "libre"
    @AppStorage("nightscout_url") var nightscoutURL = ""
    @AppStorage("nightscout_token") var nightscoutToken = ""
    @AppStorage("show_color_dot") var showColorDot = true
    @AppStorage("show_sparkline") var showSparkline = true
    @AppStorage("show_min_max") var showMinMax = true
    @AppStorage("show_prediction_line") var showPredictionLine = true

    var isNightscout: Bool { dataSource == "nightscout" }

    private var token: String?
    private var accountId: String?
    private var patientId: String?
    private var timer: Timer?

    private var baseURL: String {
        switch region {
        case "eu": return "https://api-eu.libreview.io"
        case "au": return "https://api-au.libreview.io"
        case "de": return "https://api-de.libreview.io"
        case "fr": return "https://api-fr.libreview.io"
        case "jp": return "https://api-jp.libreview.io"
        case "ap": return "https://api-ap.libreview.io"
        case "ca": return "https://api-ca.libreview.io"
        default:   return "https://api-\(region).libreview.io"
        }
    }

    private var password: String? {
        get { KeychainHelper.load(account: "libre_password") }
        set {
            if let v = newValue { KeychainHelper.save(account: "libre_password", value: v) }
            else { KeychainHelper.delete(account: "libre_password") }
        }
    }

    var analysis: String? {
        guard let reading = latestReading, !history.isEmpty else { return nil }

        let low = lowThreshold
        let high = highThreshold

        var parts: [String] = []

        // Current status
        if reading.value < low {
            let below = useMgdl ? String(format: "%.0f", (low - reading.value) * 18.0182) : String(format: "%.1f", low - reading.value)
            parts.append("Currently \(below) \(useMgdl ? "mg/dL" : "mmol/L") below target.")
        } else if reading.value > high {
            let above = useMgdl ? String(format: "%.0f", (reading.value - high) * 18.0182) : String(format: "%.1f", reading.value - high)
            parts.append("Currently \(above) \(useMgdl ? "mg/dL" : "mmol/L") above target.")
        } else {
            parts.append("Currently in range.")
        }

        // Trend
        if let rate = rateOfChange {
            let trend: String
            if rate > 0.05 {
                trend = "rising"
            } else if rate < -0.05 {
                trend = "falling"
            } else {
                trend = "stable"
            }
            parts.append("Glucose is \(trend).")
        }

        // Last out of range
        let outOfRange = history.filter { $0.value < low || $0.value > high }
        if let lastOut = outOfRange.last {
            let mins = Int(Date().timeIntervalSince(lastOut.timestamp) / 60)
            let timeAgo: String
            if mins < 60 {
                timeAgo = "\(mins) min ago"
            } else {
                let hours = mins / 60
                timeAgo = hours == 1 ? "1 hour ago" : "\(hours) hours ago"
            }
            let val = lastOut.displayFormatted(mgdl: useMgdl)
            let unit = GlucoseReading.displayUnit(mgdl: useMgdl)
            let direction = lastOut.value < low ? "low" : "high"
            parts.append("Last \(direction) was \(val) \(unit), \(timeAgo).")
        } else {
            parts.append("No out-of-range readings in recent history.")
        }

        return parts.joined(separator: " ")
    }

    init() {
        if isNightscout {
            if !nightscoutURL.isEmpty {
                Task { await fetchGlucose() }
            }
        } else if !email.isEmpty && password != nil {
            Task { await fetchGlucose() }
        }
        startTimer()
    }

    func clearData() {
        latestReading = nil
        history = []
        rateOfChange = nil
        errorMessage = nil
        sensorDaysRemaining = nil
        connections = []
        token = nil
        accountId = nil
        patientId = nil
    }

    func configure(email: String, password: String, region: String) {
        self.email = email
        self.password = password
        self.region = region
        self.token = nil
        Task { await fetchGlucose() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.fetchGlucose() }
        }
    }

    func fetchGlucose() async {
        if isNightscout {
            await fetchNightscout()
        } else {
            await fetchLibreLinkUp()
        }
    }

    private func fetchLibreLinkUp() async {
        guard !email.isEmpty, let password else {
            errorMessage = "Set credentials in Settings"
            return
        }

        do {
            if token == nil {
                token = try await login(email: email, password: password)
            }
            let (reading, pid) = try await getLatestReading()
            self.latestReading = reading
            self.patientId = pid
            self.errorMessage = nil

            if let pid {
                let graphReadings = try await getGraphData(patientId: pid)
                let logbookReadings = try await getLogbookData(patientId: pid)

                var merged: [Date: GlucoseReading] = [:]
                for r in logbookReadings { merged[r.timestamp] = r }
                for r in graphReadings { merged[r.timestamp] = r }
                self.history = merged.values.sorted { $0.timestamp < $1.timestamp }

                self.rateOfChange = Self.computeRate(from: graphReadings)
            }
        } catch LibreError.redirect(let newRegion) {
            self.region = newRegion
            self.token = nil
            await fetchGlucose()
        } catch LibreError.unauthorized {
            self.token = nil
            errorMessage = "Login failed — check credentials"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchNightscout() async {
        guard !nightscoutURL.isEmpty else {
            errorMessage = "Set Nightscout URL in Settings"
            return
        }

        do {
            let readings = try await getNightscoutEntries(count: 288)
            guard let latest = readings.last else {
                errorMessage = "No Nightscout data found"
                return
            }
            self.latestReading = latest
            self.history = readings
            self.rateOfChange = Self.computeRate(from: readings)
            self.sensorDaysRemaining = nil
            self.connections = []
            self.errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func getNightscoutEntries(count: Int) async throws -> [GlucoseReading] {
        var urlString = nightscoutURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        urlString += "/api/v1/entries/sgv.json?count=\(count)"
        if !nightscoutToken.isEmpty {
            urlString += "&token=\(nightscoutToken)"
        }

        guard let url = URL(string: urlString) else {
            throw LibreError.detailed("Invalid Nightscout URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LibreError.detailed("Unexpected Nightscout response")
        }

        return entries.compactMap { entry in
            guard let sgv = entry["sgv"] as? Double,
                  let dateMs = entry["date"] as? Double else { return nil }

            let direction = entry["direction"] as? String ?? ""
            let arrow = Self.nightscoutArrow(direction)
            let mmol = sgv / 18.0182

            return GlucoseReading(
                value: mmol,
                trendArrow: arrow,
                timestamp: Date(timeIntervalSince1970: dateMs / 1000.0),
                unit: "mmol/L"
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    static func nightscoutArrow(_ direction: String) -> String {
        switch direction {
        case "DoubleDown": return "↓↓"
        case "SingleDown": return "↓"
        case "FortyFiveDown": return "↘"
        case "Flat": return "→"
        case "FortyFiveUp": return "↗"
        case "SingleUp": return "↑"
        case "DoubleUp": return "↑↑"
        default: return "?"
        }
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("llu.ios", forHTTPHeaderField: "product")
        request.setValue("4.16.0", forHTTPHeaderField: "version")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let accountId { request.setValue(accountId, forHTTPHeaderField: "account-id") }
        request.httpBody = body
        return request
    }

    private func login(email: String, password: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let request = makeRequest("/llu/auth/login", method: "POST", body: body)
        let (data, _) = try await URLSession.shared.data(for: request)

        let responseString = String(data: data, encoding: .utf8) ?? "nil"
        print("[LibreBar] Login response: \(responseString)")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibreError.badResponse
        }

        if let redirect = json["redirect"] as? Bool, redirect,
           let regionData = json["region"] as? String {
            throw LibreError.redirect(regionData)
        }

        if let dataObj = json["data"] as? [String: Any],
           let redirect = dataObj["redirect"] as? Bool, redirect,
           let regionData = dataObj["region"] as? String {
            throw LibreError.redirect(regionData)
        }

        if let status = json["status"] as? Int, status == 2 {
            guard let authData = json["data"] as? [String: Any],
                  let step = authData["step"] as? [String: Any],
                  let type = step["type"] as? String, type == "tou",
                  let componentProps = step["componentProps"] as? [String: Any],
                  let token = componentProps["token"] as? String else {
                throw LibreError.termsOfUse
            }
            try await acceptTermsOfUse(token: token)
            return try await login(email: email, password: password)
        }

        guard let authData = json["data"] as? [String: Any],
              let authTicket = authData["authTicket"] as? [String: Any],
              let token = authTicket["token"] as? String else {
            if let errorNum = json["error"] as? Int, errorNum != 0 {
                throw LibreError.unauthorized
            }
            throw LibreError.detailed(responseString)
        }

        if let user = authData["user"] as? [String: Any],
           let userId = user["id"] as? String {
            let hash = SHA256.hash(data: Data(userId.utf8))
            self.accountId = hash.map { String(format: "%02x", $0) }.joined()
        }

        return token
    }

    private func acceptTermsOfUse(token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        let request = makeRequest("/auth/continue/tou", method: "POST", body: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        print("[LibreBar] TOU response: \(String(data: data, encoding: .utf8) ?? "nil")")
    }

    private func getLatestReading() async throws -> (GlucoseReading, String?) {
        let connRequest = makeRequest("/llu/connections")
        let (connData, _) = try await URLSession.shared.data(for: connRequest)

        let connResponseString = String(data: connData, encoding: .utf8) ?? "nil"
        print("[LibreBar] Connections response: \(connResponseString)")

        guard let connJson = try JSONSerialization.jsonObject(with: connData) as? [String: Any],
              let allConnections = connJson["data"] as? [[String: Any]],
              !allConnections.isEmpty else {
            throw LibreError.detailed(connResponseString)
        }

        self.connections = allConnections.compactMap { conn in
            guard let pid = conn["patientId"] as? String,
                  let first = conn["firstName"] as? String,
                  let last = conn["lastName"] as? String else { return nil }
            return LibreConnection(id: pid, firstName: first, lastName: last)
        }

        if selectedConnectionId.isEmpty, let firstId = connections.first?.id {
            selectedConnectionId = firstId
        }

        let selected = allConnections.first { ($0["patientId"] as? String) == selectedConnectionId }
            ?? allConnections.first!

        guard let glucoseMeasurement = selected["glucoseMeasurement"] as? [String: Any],
              let valueInMgPerDl = glucoseMeasurement["ValueInMgPerDl"] as? Double,
              let trendType = glucoseMeasurement["TrendArrow"] as? Int,
              let timestamp = glucoseMeasurement["Timestamp"] as? String else {
            throw LibreError.noData
        }

        let patientId = selected["patientId"] as? String
        let displayValue = valueInMgPerDl / 18.0182

        if let sensor = selected["sensor"] as? [String: Any],
           let activationEpoch = sensor["a"] as? Double {
            let activation = Date(timeIntervalSince1970: activationEpoch)
            let elapsed = Date().timeIntervalSince(activation) / 86400
            self.sensorDaysRemaining = max(0, 14 - Int(elapsed))
        } else if let sensor = selected["sensor"] as? [String: Any],
                  let activationInt = sensor["a"] as? Int {
            let activation = Date(timeIntervalSince1970: Double(activationInt))
            let elapsed = Date().timeIntervalSince(activation) / 86400
            self.sensorDaysRemaining = max(0, 14 - Int(elapsed))
        }

        let reading = GlucoseReading(
            value: displayValue,
            trendArrow: Self.trendArrow(for: trendType),
            timestamp: Self.parseTimestamp(timestamp),
            unit: "mmol/L"
        )
        return (reading, patientId)
    }

    private func getGraphData(patientId: String) async throws -> [GlucoseReading] {
        let request = makeRequest("/llu/connections/\(patientId)/graph")
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let graphData = json["data"] as? [String: Any],
              let measurements = graphData["graphData"] as? [[String: Any]] else {
            // Non-critical — just return empty history
            print("[LibreBar] Graph parse failed: \(String(data: data, encoding: .utf8) ?? "nil")")
            return []
        }

        return measurements.compactMap { m in
            guard let mgdl = m["ValueInMgPerDl"] as? Double,
                  let ts = m["Timestamp"] as? String else { return nil }
            return GlucoseReading(
                value: mgdl / 18.0182,
                trendArrow: "",
                timestamp: Self.parseTimestamp(ts),
                unit: "mmol/L"
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    private func getLogbookData(patientId: String) async throws -> [GlucoseReading] {
        let request = makeRequest("/llu/connections/\(patientId)/logbook")
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else {
            print("[LibreBar] Logbook parse failed: \(String(data: data, encoding: .utf8) ?? "nil")")
            return []
        }

        var readings: [GlucoseReading] = []

        for entry in entries {
            if let mgdl = entry["ValueInMgPerDl"] as? Double,
               let ts = entry["Timestamp"] as? String {
                readings.append(GlucoseReading(
                    value: mgdl / 18.0182,
                    trendArrow: "",
                    timestamp: Self.parseTimestamp(ts),
                    unit: "mmol/L"
                ))
            }
        }

        return readings.sorted { $0.timestamp < $1.timestamp }
    }

    static func computeRate(from readings: [GlucoseReading]) -> Double? {
        guard readings.count >= 2 else { return nil }
        let recent = readings.suffix(3)
        guard let first = recent.first, let last = recent.last else { return nil }
        let timeDelta = last.timestamp.timeIntervalSince(first.timestamp) / 60.0
        guard timeDelta > 0 else { return nil }
        return (last.value - first.value) / timeDelta
    }

    static func parseTimestamp(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        return formatter.date(from: string) ?? Date()
    }

    static func trendArrow(for type: Int) -> String {
        switch type {
        case 1: return "↓"
        case 2: return "↘"
        case 3: return "→"
        case 4: return "↗"
        case 5: return "↑"
        default: return "?"
        }
    }
}

enum LibreError: Error, LocalizedError {
    case unauthorized
    case badResponse
    case noData
    case redirect(String)
    case termsOfUse
    case detailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Login failed"
        case .badResponse: return "Unexpected response"
        case .noData: return "No glucose data found"
        case .redirect(let r): return "Redirecting to \(r)"
        case .termsOfUse: return "Terms of use acceptance failed"
        case .detailed(let d): return "API error: \(d.prefix(200))"
        }
    }
}
