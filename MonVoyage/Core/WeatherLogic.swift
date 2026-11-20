import Foundation

/// Choix de la source météo pour un jour donné.
enum WeatherSource: Equatable {
    /// Prévision Open-Meteo (jour à 16 jours ou moins).
    case forecast
    /// « Normales » : mêmes dates l'année précédente (archive).
    case normals(previousYearKey: String)
}

enum WeatherLogic {
    static let forecastHorizonDays = 16

    static func source(for dayKey: String, now: Date = Date()) -> WeatherSource {
        guard let day = DayKey.date(fromKey: dayKey) else { return .normals(previousYearKey: dayKey) }
        let delta = DayMath.daysBetween(now, day)
        if delta >= -2 && delta < forecastHorizonDays { return .forecast }
        return .normals(previousYearKey: previousYearKey(dayKey))
    }

    static func previousYearKey(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]) else { return key }
        var month = String(parts[1]), day = String(parts[2])
        if month == "02" && day == "29" { month = "02"; day = "28" }
        return String(format: "%04d-%@-%@", year - 1, month, day)
    }

    /// Code météo WMO → symbole SF et libellé.
    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    static func label(for code: Int) -> String {
        switch code {
        case 0: return "Ensoleillé"
        case 1, 2: return "Éclaircies"
        case 3: return "Couvert"
        case 45, 48: return "Brouillard"
        case 51...57: return "Bruine"
        case 61...67, 80...82: return "Pluie"
        case 71...77, 85, 86: return "Neige"
        case 95...99: return "Orages"
        default: return "Variable"
        }
    }
}

/// Niveau d'affluence 1–10 → libellé et couleur.
enum CrowdScale {
    static func label(for level: Int) -> String {
        switch level {
        case ...2: return "Très calme"
        case 3...4: return "Calme"
        case 5...6: return "Modéré"
        case 7...8: return "Chargé"
        default: return "Très chargé"
        }
    }

    /// Index de couleur : 0 vert … 4 rouge.
    static func colorIndex(for level: Int) -> Int {
        switch level {
        case ...2: return 0
        case 3...4: return 1
        case 5...6: return 2
        case 7...8: return 3
        default: return 4
        }
    }
}
