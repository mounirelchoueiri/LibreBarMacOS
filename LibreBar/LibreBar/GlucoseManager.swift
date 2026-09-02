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

    func clipboardString(mgdl: Bool) -> String {
        let unit = GlucoseReading.displayUnit(mgdl: mgdl)
        let trend = trendArrow.isEmpty ? "" : " \(trendArrow)"
        return "\(displayFormatted(mgdl: mgdl)) \(unit)\(trend)"
    }

    static func displayUnit(mgdl: Bool) -> String {
        mgdl ? "mg/dL" : "mmol/L"
    }

    var minutesAgo: Int {
        Int(Date().timeIntervalSince(timestamp) / 60)
    }

    var isStale: Bool { minutesAgo > 15 }
}

enum ConnectionStatus: Equatable {
    case loading
    case connected
    case offline(since: Date)
    case error(String)
    case unconfigured
}

@MainActor
class GlucoseManager: ObservableObject {
    @Published var latestReading: GlucoseReading?
    @Published var history: [GlucoseReading] = []
    @Published var rateOfChange: Double?
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var connections: [LibreConnection] = []
    @Published var sensorExpirationDate: Date?
    @Published var connectionStatus: ConnectionStatus = .loading

    @AppStorage("last_successful_fetch") private var lastSuccessfulFetchTimestamp: Double = 0
    @AppStorage("libre_lockout_until") private var lockoutUntilTimestamp: Double = 0

    private var lockoutUntil: Date? {
        lockoutUntilTimestamp > 0 ? Date(timeIntervalSince1970: lockoutUntilTimestamp) : nil
    }

    private func recordLockout(seconds: Int) {
        lockoutUntilTimestamp = Date().addingTimeInterval(TimeInterval(seconds)).timeIntervalSince1970
    }

    private func clearLockout() {
        lockoutUntilTimestamp = 0
    }

    private func lockoutErrorIfActive() -> String? {
        guard let until = lockoutUntil, until > Date() else {
            if lockoutUntilTimestamp > 0 { clearLockout() }
            return nil
        }
        return LibreError.accountLocked(seconds: max(1, Int(until.timeIntervalSinceNow))).localizedDescription
    }

    private var lastSuccessfulFetch: Date? {
        lastSuccessfulFetchTimestamp > 0 ? Date(timeIntervalSince1970: lastSuccessfulFetchTimestamp) : nil
    }

    private func markSuccess() {
        lastSuccessfulFetchTimestamp = Date().timeIntervalSince1970
        connectionStatus = .connected
    }

    private func markFailure(_ message: String) {
        if latestReading != nil {
            connectionStatus = .offline(since: lastSuccessfulFetch ?? Date())
        } else {
            connectionStatus = .error(message)
        }
    }

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

    var sensorRemainingText: String? {
        guard let expiration = sensorExpirationDate else { return nil }

        let remaining = expiration.timeIntervalSinceNow
        guard remaining > 0 else { return "Sensor expired" }

        let totalHours = Int(ceil(remaining / 3600))
        if totalHours <= 24 {
            let time = expiration.formatted(date: .omitted, time: .shortened)
            if Calendar.current.isDateInToday(expiration) {
                return "Expires today at \(time)"
            }
            if Calendar.current.isDateInTomorrow(expiration) {
                return "Expires tomorrow at \(time)"
            }
            return "Expires \(expiration.formatted(date: .abbreviated, time: .shortened))"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        return hours == 0 ? "Sensor \(days)d left" : "Sensor \(days)d \(hours)h left"
    }

    private var token: String?
    private var accountId: String?
    private var patientId: String?
    private var timer: Timer?

    private func resetAuthSession() {
        token = nil
        accountId = nil
    }

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
        sensorExpirationDate = nil
        connections = []
        connectionStatus = .loading
        token = nil
        accountId = nil
        patientId = nil
    }

    func configure(email: String, password: String, region: String) {
        self.email = email
        self.password = password
        self.region = region
        resetAuthSession()
        Task { await fetchGlucose() }
    }

    func configureAndFetch(email: String, password: String, region: String) async {
        self.email = email
        self.password = password
        self.region = region
        resetAuthSession()
        await fetchGlucose()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.fetchGlucose(allowLogin: false) }
        }
    }

    func fetchGlucose(allowLogin: Bool = true) async {
        if isNightscout {
            await fetchNightscout()
        } else {
            await fetchLibreLinkUp(allowLogin: allowLogin)
        }
    }

    private func fetchLibreLinkUp(allowLogin: Bool) async {
        guard !email.isEmpty, let password else {
            errorMessage = "Set credentials in Settings"
            connectionStatus = .unconfigured
            return
        }

        if let lockoutMessage = lockoutErrorIfActive() {
            errorMessage = lockoutMessage
            connectionStatus = .error(lockoutMessage)
            return
        }

        do {
            if token == nil {
                // Background refreshes may reuse a session, but must never perform login.
                guard allowLogin else { return }
                token = try await login(email: email, password: password)
            }
            let (reading, pid) = try await getLatestReading()
            self.latestReading = reading
            self.patientId = pid
            self.errorMessage = nil
            markSuccess()
            clearLockout()
            AlertManager.shared.evaluateConnectionError(nil)

            if let pid {
                let graphReadings = try await getGraphData(patientId: pid)
                let logbookReadings = try await getLogbookData(patientId: pid)

                var merged: [Date: GlucoseReading] = [:]
                for r in logbookReadings { merged[r.timestamp] = r }
                for r in graphReadings { merged[r.timestamp] = r }
                self.history = merged.values.sorted { $0.timestamp < $1.timestamp }

                self.rateOfChange = Self.computeRate(from: graphReadings)
            }
            AlertManager.shared.evaluate(reading: reading, low: lowThreshold, high: highThreshold, useMgdl: useMgdl)
        } catch LibreError.redirect(let newRegion) {
            self.region = newRegion
            resetAuthSession()
            await fetchGlucose(allowLogin: allowLogin)
        } catch LibreError.unauthorized {
            resetAuthSession()
            errorMessage = "Login failed — check credentials"
            connectionStatus = .error(errorMessage!)
            AlertManager.shared.evaluateConnectionError(errorMessage)
        } catch LibreError.termsOfUse {
            resetAuthSession()
            let message = LibreError.termsOfUse.localizedDescription
            errorMessage = message
            connectionStatus = .error(message)
            AlertManager.shared.evaluateConnectionError(message)
        } catch LibreError.accountLocked(let seconds) {
            resetAuthSession()
            recordLockout(seconds: seconds)
            let message = LibreError.accountLocked(seconds: seconds).localizedDescription
            errorMessage = message
            connectionStatus = .error(message)
            AlertManager.shared.evaluateConnectionError(message)
        } catch {
            markFailure(error.localizedDescription)
            errorMessage = latestReading == nil ? error.localizedDescription : nil
            AlertManager.shared.evaluateConnectionError(error.localizedDescription)
        }
    }

    private func fetchNightscout() async {
        guard !nightscoutURL.isEmpty else {
            errorMessage = "Set Nightscout URL in Settings"
            connectionStatus = .unconfigured
            return
        }

        do {
            let readings = try await getNightscoutEntries(count: 288)
            guard let latest = readings.last else {
                errorMessage = "No Nightscout data found"
                connectionStatus = .error(errorMessage!)
                return
            }
            self.latestReading = latest
            self.history = readings
            self.rateOfChange = Self.computeRate(from: readings)
            self.sensorExpirationDate = nil
            self.connections = []
            self.errorMessage = nil
            markSuccess()
            AlertManager.shared.evaluateConnectionError(nil)
            AlertManager.shared.evaluate(reading: latest, low: lowThreshold, high: highThreshold, useMgdl: useMgdl)
        } catch {
            markFailure(error.localizedDescription)
            errorMessage = latestReading == nil ? error.localizedDescription : nil
            AlertManager.shared.evaluateConnectionError(error.localizedDescription)
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

    private static let apiVersion = "4.16.0"
    private static let userAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"

    private func applyLibreHeaders(to request: inout URLRequest, bearerToken: String? = nil) {
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("llu.android", forHTTPHeaderField: "product")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "version")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        } else if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let accountId { request.setValue(accountId, forHTTPHeaderField: "account-id") }
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        applyLibreHeaders(to: &request)
        request.httpBody = body
        return request
    }

    /// Detects LibreLinkUp rate-limit lockouts (HTTP 429 / message "locked").
    private static func lockedLockoutSeconds(from json: [String: Any]) -> Int? {
        let status = json["status"] as? Int
        guard let data = json["data"] as? [String: Any] else {
            return status == 429 ? 300 : nil
        }

        let message = data["message"] as? String
        let isLocked = status == 429 || message == "locked"
        guard isLocked else { return nil }

        if let seconds = lockoutSeconds(in: data) ?? lockoutSeconds(in: data["data"]) {
            return seconds
        }
        return 300
    }

    private static func lockoutSeconds(in value: Any?) -> Int? {
        guard let dict = value as? [String: Any] else { return nil }
        if let lockout = dict["lockout"] as? Int { return lockout }
        if let lockout = dict["lockout"] as? Double { return Int(lockout) }
        return nil
    }

    private static func throwIfLocked(_ json: [String: Any]) throws {
        if let seconds = lockedLockoutSeconds(from: json) {
            throw LibreError.accountLocked(seconds: seconds)
        }
    }

    /// True when LibreLinkUp requires accepting terms (tou) or privacy policy (pp).
    private static func requiresAuthStep(_ json: [String: Any]) -> Bool {
        if (json["status"] as? Int) == 4 { return true }
        guard let data = json["data"] as? [String: Any],
              let step = data["step"] as? [String: Any],
              let type = step["type"] as? String else { return false }
        return type == "tou" || type == "pp"
    }

    private static func extractAuthStep(from json: [String: Any]) -> (type: String, token: String)? {
        guard let data = json["data"] as? [String: Any],
              let step = data["step"] as? [String: Any],
              let stepType = step["type"] as? String,
              let authTicket = data["authTicket"] as? [String: Any],
              let stepToken = authTicket["token"] as? String,
              !stepToken.isEmpty else { return nil }
        return (stepType, stepToken)
    }

    private func login(email: String, password: String) async throws -> String {
        var json = try await performLoginRequest(email: email, password: password)

        if Self.requiresAuthStep(json) {
            json = try await handleRequiredAuthSteps(json)
            try Self.throwIfLocked(json)
        }

        try Self.throwIfLocked(json)

        guard let token = extractAuthToken(from: json) else {
            if Self.requiresAuthStep(json) {
                throw LibreError.termsOfUse
            }
            if let errorNum = json["error"] as? Int, errorNum != 0 {
                throw LibreError.unauthorized
            }
            let responseString = (try? JSONSerialization.data(withJSONObject: json))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            throw LibreError.detailed(responseString)
        }

        extractAccountId(from: json)
        return token
    }

    private func extractAuthToken(from json: [String: Any]) -> String? {
        guard let authData = json["data"] as? [String: Any],
              let authTicket = authData["authTicket"] as? [String: Any] else { return nil }
        return authTicket["token"] as? String
    }

    private func extractAccountId(from json: [String: Any]) {
        guard let authData = json["data"] as? [String: Any],
              let user = authData["user"] as? [String: Any],
              let userId = user["id"] as? String else { return }
        let hash = SHA256.hash(data: Data(userId.utf8))
        self.accountId = hash.map { String(format: "%02x", $0) }.joined()
    }

    private func performLoginRequest(email: String, password: String) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let request = makeRequest("/llu/auth/login", method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibreError.badResponse
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 429,
           Self.lockedLockoutSeconds(from: json) == nil {
            throw LibreError.accountLocked(seconds: 300)
        }

        try Self.throwIfLocked(json)

        if let redirect = json["redirect"] as? Bool, redirect,
           let regionData = json["region"] as? String {
            throw LibreError.redirect(regionData)
        }

        if let dataObj = json["data"] as? [String: Any],
           let redirect = dataObj["redirect"] as? Bool, redirect,
           let regionData = dataObj["region"] as? String {
            throw LibreError.redirect(regionData)
        }

        return json
    }

    /// Accepts required tou/pp steps. Each POST /auth/continue/{type} may chain (tou → pp).
    private func handleRequiredAuthSteps(_ json: [String: Any]) async throws -> [String: Any] {
        var current = json

        for _ in 0..<5 {
            guard Self.requiresAuthStep(current) else { return current }

            guard let step = Self.extractAuthStep(from: current) else {
                throw LibreError.termsOfUse
            }

            current = try await acceptContinueStep(type: step.type, bearerToken: step.token)
        }

        if Self.requiresAuthStep(current) {
            throw LibreError.termsOfUse
        }

        return current
    }

    private func acceptContinueStep(type: String, bearerToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: baseURL + "/auth/continue/\(type)")!)
        request.httpMethod = "POST"
        applyLibreHeaders(to: &request, bearerToken: bearerToken)
        // LibreLinkUp expects an empty body for continue requests.

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LibreError.badResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibreError.badResponse
        }

        try Self.throwIfLocked(json)

        if http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LibreError.detailed("Continue \(type) failed: \(msg.prefix(200))")
        }

        return json
    }

    private func parseLibreDataResponse(
        data: Data,
        response: URLResponse
    ) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibreError.badResponse
        }

        if http.statusCode == 429, Self.lockedLockoutSeconds(from: json) == nil {
            throw LibreError.accountLocked(seconds: 300)
        }
        try Self.throwIfLocked(json)

        if http.statusCode == 401 {
            throw LibreError.unauthorized
        }

        if !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LibreError.detailed(message)
        }

        if Self.requiresAuthStep(json) {
            throw LibreError.termsOfUse
        }

        if let status = json["status"] as? Int, status != 0 {
            let message = String(data: data, encoding: .utf8) ?? "API status \(status)"
            throw LibreError.detailed(message)
        }

        return json
    }

    private func getLatestReading() async throws -> (GlucoseReading, String?) {
        let connRequest = makeRequest("/llu/connections")
        let (connData, connResponse) = try await URLSession.shared.data(for: connRequest)

        let connResponseString = String(data: connData, encoding: .utf8) ?? "nil"

        let connJson = try parseLibreDataResponse(data: connData, response: connResponse)
        guard let allConnections = connJson["data"] as? [[String: Any]],
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
           let activationEpoch = (sensor["a"] as? NSNumber)?.doubleValue {
            let activation = Date(timeIntervalSince1970: activationEpoch)
            // Libre 3 Plus sensors run for 15 days (360 hours).
            self.sensorExpirationDate = activation.addingTimeInterval(15 * 24 * 60 * 60)
        } else {
            self.sensorExpirationDate = nil
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
        let (data, response) = try await URLSession.shared.data(for: request)

        let json = try parseLibreDataResponse(data: data, response: response)
        guard let graphData = json["data"] as? [String: Any],
              let measurements = graphData["graphData"] as? [[String: Any]] else {
            // Non-critical — just return empty history
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
        let (data, response) = try await URLSession.shared.data(for: request)

        let json = try parseLibreDataResponse(data: data, response: response)
        guard let entries = json["data"] as? [[String: Any]] else {
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
    case accountLocked(seconds: Int)
    case detailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Login failed — check credentials"
        case .badResponse: return "Unexpected response"
        case .noData: return "No glucose data found"
        case .redirect(let r): return "Redirecting to \(r)"
        case .termsOfUse: return "Could not accept terms — open the LibreLinkUp app on your phone, log out and back in, accept any prompts, then try again"
        case .accountLocked(let seconds):
            let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
            return "Too many login attempts — LibreLinkUp locked your account. Wait \(minutes) min, accept terms in the mobile app, then try again"
        case .detailed(let d): return "API error: \(d.prefix(200))"
        }
    }
}
