import Foundation
import Combine

/// Réglages de l'appli (stockés localement sur l'iPhone).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var airportLeadHours: Int { didSet { defaults.set(airportLeadHours, forKey: "airportLeadHours") } }
    @Published var estaReminderDays: Int { didSet { defaults.set(estaReminderDays, forKey: "estaReminderDays") } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var lastExportDate: Date? { didSet { defaults.set(lastExportDate, forKey: "lastExportDate") } }
    @Published var exportReminderDismissedAt: Date? { didSet { defaults.set(exportReminderDismissedAt, forKey: "exportReminderDismissedAt") } }

    init() {
        let lead = defaults.integer(forKey: "airportLeadHours")
        airportLeadHours = lead > 0 ? lead : 3
        let esta = defaults.integer(forKey: "estaReminderDays")
        estaReminderDays = esta > 0 ? esta : 30
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        lastExportDate = defaults.object(forKey: "lastExportDate") as? Date
        exportReminderDismissedAt = defaults.object(forKey: "exportReminderDismissedAt") as? Date
    }

    /// Rappel discret si aucun export depuis 30 jours.
    var shouldRemindExport: Bool {
        let reference = [lastExportDate, exportReminderDismissedAt].compactMap { $0 }.max()
        guard let reference else { return true }
        return Date().timeIntervalSince(reference) > 30 * 86400
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
