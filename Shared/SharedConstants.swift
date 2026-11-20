import Foundation

/// Valeurs partagées entre l'appli et l'extension widget.
/// Les identifiants réels viennent de l'Info.plist (eux-mêmes définis dans project.yml).
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.fr.tanguy.monvoyage"
    }

    /// Dossier du conteneur App Group (caches JSON lisibles par le widget).
    /// Repli sur Application Support si l'App Group n'est pas disponible (tests, simulateur non signé).
    static var containerURL: URL {
        let url: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            url = group
        } else {
            url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AppGroupFallback", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

enum SharedKeys {
    static let pendingQuickAdd = "pendingQuickAdd"
    static let widgetSnapshotFile = "widget-snapshot.json"
}

enum SharedLocale {
    static let fr = Locale(identifier: "fr_FR")
}

/// Formats français (1 234,56 €, « lun. 11 mai », °C).
enum Fmt {
    static func eur(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(SharedLocale.fr))
    }

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(SharedLocale.fr))
    }

    static func money(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).locale(SharedLocale.fr))
    }

    static func eurShort(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").precision(.fractionLength(0)).locale(SharedLocale.fr))
    }

    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(locale: SharedLocale.fr, timeZone: timeZone)
        style = style.weekday(.abbreviated).day().month(.abbreviated)
        return date.formatted(style)
    }

    static func longDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(locale: SharedLocale.fr, timeZone: timeZone)
        style = style.weekday(.wide).day().month(.wide)
        return date.formatted(style)
    }

    static func dateShort(_ date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(locale: SharedLocale.fr, timeZone: timeZone)
        style = style.day().month(.abbreviated).year()
        return date.formatted(style)
    }

    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(locale: SharedLocale.fr, timeZone: timeZone)
        style = style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return date.formatted(style)
    }

    static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        "\(day(date, timeZone: timeZone)) à \(time(date, timeZone: timeZone))"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).locale(SharedLocale.fr))
    }

    static func temp(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°C"
    }

    static func number(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).locale(SharedLocale.fr))
    }

    static func updated(_ date: Date?) -> String {
        guard let date else { return "jamais mis à jour" }
        return "mis à jour " + date.formatted(.relative(presentation: .named).locale(SharedLocale.fr))
    }
}

/// Calculs de jours partagés (compte à rebours).
enum DayMath {
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
