import Foundation

/// Gestion des « jours » : une date de jour est stockée à midi (heure locale de saisie),
/// ce qui la garde sur le même jour calendaire quel que soit le fuseau (±11 h).
enum DayKey {
    static func calendar(_ timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = SharedLocale.fr
        return cal
    }

    /// "yyyy-MM-dd"
    static func key(_ date: Date, timeZone: TimeZone = .current) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func noon(_ date: Date, timeZone: TimeZone = .current) -> Date {
        let cal = calendar(timeZone)
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = 12
        return cal.date(from: c) ?? date
    }

    static func date(fromKey key: String, timeZone: TimeZone = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return calendar(timeZone).date(from: c)
    }

    static func days(from start: Date, to end: Date) -> [Date] {
        let cal = calendar()
        var current = noon(start)
        let last = noon(end)
        var result: [Date] = []
        var guardCount = 0
        while current <= last && guardCount < 400 {
            result.append(current)
            current = cal.date(byAdding: .day, value: 1, to: current) ?? last.addingTimeInterval(1)
            guardCount += 1
        }
        return result
    }

    /// Combine un jour et une heure (h:m) dans le fuseau donné.
    static func combine(dayKey: String, hour: Int, minute: Int, timeZone: TimeZone) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = hour; c.minute = minute
        return calendar(timeZone).date(from: c)
    }

    static func endOfDay(_ date: Date, timeZone: TimeZone = .current) -> Date {
        let cal = calendar(timeZone)
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
