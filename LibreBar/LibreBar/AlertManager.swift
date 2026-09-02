import Foundation
import UserNotifications
import AppKit

enum GlucoseState: Equatable {
    case urgentLow, low, inRange, high, urgentHigh

    static func from(value: Double, low: Double, high: Double) -> GlucoseState {
        let urgentLow = low - 0.8
        let urgentHigh = high + 3.9
        switch value {
        case ..<urgentLow:      return .urgentLow
        case urgentLow..<low:   return .low
        case low...high:        return .inRange
        case high...urgentHigh: return .high
        default:                return .urgentHigh
        }
    }
}

@MainActor
final class AlertManager {
    static let shared = AlertManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private var lastState: GlucoseState?
    private var lastStaleNotified = false
    private var lastConnectionFailed = false

    static let openActionID = "OPEN_LIBREBAR"
    static let snoozeActionID = "SNOOZE_30"
    static let categoryID = "GLUCOSE_ALERT"

    // MARK: - Settings accessors

    var enabled: Bool { defaults.boolOrDefault(AlertKey.enabled, false) }
    private var alertLow: Bool { defaults.boolOrDefault(AlertKey.low, true) }
    private var alertHigh: Bool { defaults.boolOrDefault(AlertKey.high, true) }
    private var alertUrgent: Bool { defaults.boolOrDefault(AlertKey.urgent, true) }
    private var alertStale: Bool { defaults.boolOrDefault(AlertKey.stale, true) }
    private var alertConnection: Bool { defaults.boolOrDefault(AlertKey.connection, true) }
    private var soundOnUrgent: Bool { defaults.boolOrDefault(AlertKey.sound, true) }
    private var snoozeMinutes: Int {
        let m = defaults.integer(forKey: AlertKey.snoozeMinutes)
        return m == 0 ? 30 : m
    }

    // MARK: - Setup

    func registerCategories() {
        let open = UNNotificationAction(identifier: Self.openActionID, title: "Open LibreBar", options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.snoozeActionID, title: "Snooze 30m", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [open, snooze], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Snooze

    var isSnoozed: Bool {
        guard let until = defaults.object(forKey: AlertKey.snoozeUntil) as? Date else { return false }
        return until > Date()
    }

    func snooze(minutes: Int? = nil) {
        let m = minutes ?? snoozeMinutes
        defaults.set(Date().addingTimeInterval(Double(m) * 60), forKey: AlertKey.snoozeUntil)
    }

    func clearSnooze() {
        defaults.removeObject(forKey: AlertKey.snoozeUntil)
    }

    // MARK: - Evaluation

    func evaluate(reading: GlucoseReading, low: Double, high: Double, useMgdl: Bool) {
        lastConnectionFailed = false
        guard enabled, !isSnoozed else {
            lastState = GlucoseState.from(value: reading.value, low: low, high: high)
            return
        }

        // Stale data
        if reading.isStale {
            if alertStale && !lastStaleNotified {
                notify(title: "Glucose data is stale",
                       body: "No new reading for \(reading.minutesAgo) minutes.",
                       urgent: false)
            }
            lastStaleNotified = true
        } else {
            lastStaleNotified = false
        }

        let state = GlucoseState.from(value: reading.value, low: low, high: high)
        defer { lastState = state }

        guard state != lastState else { return }

        let valueText = "\(reading.displayFormatted(mgdl: useMgdl)) \(GlucoseReading.displayUnit(mgdl: useMgdl))"

        switch state {
        case .urgentLow where alertUrgent:
            notify(title: "Urgent low glucose", body: "\(valueText) \(reading.trendArrow)", urgent: true)
        case .low where alertLow:
            notify(title: "Low glucose", body: "\(valueText) \(reading.trendArrow)", urgent: false)
        case .high where alertHigh:
            notify(title: "High glucose", body: "\(valueText) \(reading.trendArrow)", urgent: false)
        case .urgentHigh where alertUrgent:
            notify(title: "Urgent high glucose", body: "\(valueText) \(reading.trendArrow)", urgent: true)
        default:
            break
        }
    }

    func evaluateConnectionError(_ message: String?) {
        guard enabled, !isSnoozed, alertConnection else {
            lastConnectionFailed = (message != nil)
            return
        }
        if message != nil {
            if !lastConnectionFailed {
                notify(title: "LibreBar connection issue", body: message ?? "Unable to fetch glucose.", urgent: false)
            }
            lastConnectionFailed = true
        } else {
            lastConnectionFailed = false
        }
    }

    // MARK: - Notification delivery

    func sendTest() {
        notify(title: "LibreBar test alert", body: "Alerts are working. You'll be notified when glucose goes out of range.", urgent: false)
    }

    private func notify(title: String, body: String, urgent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.categoryID
        if urgent && soundOnUrgent {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
