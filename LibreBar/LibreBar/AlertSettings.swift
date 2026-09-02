import Foundation

enum AlertKey {
    static let enabled = "alerts_enabled"
    static let low = "alert_low"
    static let high = "alert_high"
    static let urgent = "alert_urgent"
    static let stale = "alert_stale"
    static let connection = "alert_connection"
    static let sound = "alert_sound_urgent"
    static let snoozeMinutes = "alert_snooze_minutes"
    static let snoozeUntil = "alert_snooze_until"
}

extension UserDefaults {
    func boolOrDefault(_ key: String, _ fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }
}
