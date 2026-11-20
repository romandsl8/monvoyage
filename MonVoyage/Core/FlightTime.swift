import Foundation

/// Heures de vol saisies en heure locale de chaque aéroport.
enum FlightTime {
    /// Construit l'instant absolu à partir d'une heure locale d'aéroport.
    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZone: TimeZone) -> Date? {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return DayKey.calendar(timeZone).date(from: c)
    }

    /// Durée réelle (décalage horaire pris en compte, puisque les dates sont absolues).
    static func duration(departure: Date, arrival: Date) -> TimeInterval {
        arrival.timeIntervalSince(departure)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let minutes = Int((interval / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : String(format: "%d h %02d", h, m)
    }

    /// Décalage horaire entre deux fuseaux à une date donnée (en heures).
    static func offsetHours(from: TimeZone, to: TimeZone, at date: Date) -> Double {
        Double(to.secondsFromGMT(for: date) - from.secondsFromGMT(for: date)) / 3600
    }

    /// Décalage d'une date affichée dans un fuseau vers un autre en gardant la même heure murale.
    /// Utilisé quand l'utilisateur change l'aéroport : 10:30 reste 10:30 local.
    static func keepWallTime(_ date: Date, from: TimeZone, to: TimeZone) -> Date {
        let c = DayKey.calendar(from).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return DayKey.calendar(to).date(from: c) ?? date
    }
}

/// Table locale IATA → fuseau horaire (principaux aéroports, complétable dans les Réglages).
enum Airports {
    static let builtIn: [String: String] = [
        // France / Europe
        "CDG": "Europe/Paris", "ORY": "Europe/Paris", "NCE": "Europe/Paris", "LYS": "Europe/Paris",
        "MRS": "Europe/Paris", "TLS": "Europe/Paris", "BOD": "Europe/Paris", "NTE": "Europe/Paris",
        "BSL": "Europe/Paris", "MPL": "Europe/Paris", "LIL": "Europe/Paris", "SXB": "Europe/Paris",
        "BRU": "Europe/Brussels", "GVA": "Europe/Zurich", "ZRH": "Europe/Zurich", "LHR": "Europe/London",
        "LGW": "Europe/London", "MAN": "Europe/London", "DUB": "Europe/Dublin", "AMS": "Europe/Amsterdam",
        "FRA": "Europe/Berlin", "MUC": "Europe/Berlin", "MAD": "Europe/Madrid", "BCN": "Europe/Madrid",
        "LIS": "Europe/Lisbon", "FCO": "Europe/Rome", "KEF": "Atlantic/Reykjavik", "IST": "Europe/Istanbul",
        // États-Unis
        "MCO": "America/New_York", "SFB": "America/New_York", "TPA": "America/New_York", "MIA": "America/New_York",
        "FLL": "America/New_York", "JFK": "America/New_York", "EWR": "America/New_York", "LGA": "America/New_York",
        "BOS": "America/New_York", "IAD": "America/New_York", "DCA": "America/New_York", "ATL": "America/New_York",
        "CLT": "America/New_York", "PHL": "America/New_York", "DTW": "America/Detroit", "ORD": "America/Chicago",
        "DFW": "America/Chicago", "IAH": "America/Chicago", "MSP": "America/Chicago", "DEN": "America/Denver",
        "PHX": "America/Phoenix", "LAS": "America/Los_Angeles", "LAX": "America/Los_Angeles",
        "SFO": "America/Los_Angeles", "SEA": "America/Los_Angeles", "SAN": "America/Los_Angeles",
        "HNL": "Pacific/Honolulu",
        // Canada / Caraïbes
        "YUL": "America/Toronto", "YYZ": "America/Toronto", "YVR": "America/Vancouver",
        "PTP": "America/Guadeloupe", "FDF": "America/Martinique", "PUJ": "America/Santo_Domingo",
        "CUN": "America/Cancun", "NAS": "America/Nassau",
        // Ailleurs
        "DXB": "Asia/Dubai", "DOH": "Asia/Qatar", "NRT": "Asia/Tokyo", "HND": "Asia/Tokyo",
        "SIN": "Asia/Singapore", "BKK": "Asia/Bangkok", "RUN": "Indian/Reunion", "MRU": "Indian/Mauritius"
    ]

    static let customKey = "customAirportTimeZones"

    static var custom: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: customKey) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: customKey) }
    }

    static func timeZoneID(for iata: String?) -> String? {
        guard let code = iata?.uppercased().trimmingCharacters(in: .whitespaces), code.count == 3 else { return nil }
        return custom[code] ?? builtIn[code]
    }

    static func timeZone(for iata: String?) -> TimeZone? {
        timeZoneID(for: iata).flatMap { TimeZone(identifier: $0) }
    }
}

/// Table locale code IATA compagnie → nom (complétable dans les Réglages).
enum Airlines {
    static let builtIn: [String: String] = [
        "AF": "Air France", "KL": "KLM", "DL": "Delta Air Lines", "AA": "American Airlines",
        "UA": "United Airlines", "BA": "British Airways", "LH": "Lufthansa", "IB": "Iberia",
        "TO": "Transavia", "U2": "easyJet", "FR": "Ryanair", "VS": "Virgin Atlantic",
        "B6": "JetBlue", "WN": "Southwest Airlines", "NK": "Spirit Airlines", "F9": "Frontier Airlines",
        "AC": "Air Canada", "TS": "Air Transat", "LX": "Swiss", "SN": "Brussels Airlines",
        "TP": "TAP Air Portugal", "EI": "Aer Lingus", "FI": "Icelandair", "EK": "Emirates",
        "QR": "Qatar Airways", "TK": "Turkish Airlines", "SS": "Corsair", "BF": "French bee",
        "TX": "Air Caraïbes", "UX": "Air Europa", "AS": "Alaska Airlines", "AY": "Finnair"
    ]

    /// Ouverture de l'enregistrement en ligne (heures avant le départ) par défaut.
    static let defaultCheckInHours: [String: Int] = ["AF": 30, "KL": 30, "DL": 24, "AA": 24, "UA": 24, "BA": 24]

    static let customKey = "customAirlines"
    static let checkInKey = "customCheckInHours"

    static var custom: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: customKey) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: customKey) }
    }

    static var customCheckIn: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: checkInKey) as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: checkInKey) }
    }

    static func name(for code: String?) -> String? {
        guard let code = code?.uppercased().trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
        return custom[code] ?? builtIn[code]
    }

    /// Extrait le code compagnie d'un numéro de vol (« AF 090 » → « AF »).
    static func code(fromFlightNumber number: String) -> String? {
        let cleaned = number.uppercased().replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 3 else { return nil }
        let prefix = String(cleaned.prefix(2))
        let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits)
        guard prefix.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              prefix.unicodeScalars.contains(where: { CharacterSet.uppercaseLetters.contains($0) }) else { return nil }
        return prefix
    }

    static func checkInHours(for code: String?) -> Int {
        let c = (code ?? "").uppercased()
        return customCheckIn[c] ?? defaultCheckInHours[c] ?? 24
    }
}
