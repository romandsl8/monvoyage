import Foundation
import SwiftUI

/// Une journée d'ouverture d'un parc (heures locales du parc).
struct ParkDayHours: Codable, Hashable {
    struct Slot: Codable, Hashable {
        let open: Date
        let close: Date
        let label: String
    }
    let dayKey: String          // yyyy-MM-dd (date locale du parc)
    let open: Date?
    let close: Date?
    let extra: [Slot]           // ouverture anticipée, soirées payantes…

    var isClosed: Bool { open == nil }
}

struct ParkSchedule: Codable {
    let timeZoneID: String
    let fetchedAt: Date
    let days: [ParkDayHours]

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    func day(_ key: String) -> ParkDayHours? { days.first { $0.dayKey == key } }
    var lastKey: String? { days.map(\.dayKey).max() }
}

/// Horaires d'ouverture (ThemeParks.wiki, gratuit, sans clé).
/// Les parcs Queue-Times sont associés aux parcs ThemeParks.wiki par nom puis par distance.
@MainActor
final class ParkHoursService: ObservableObject {
    static let shared = ParkHoursService()

    @Published private(set) var schedules: [Int64: ParkSchedule] = [:]
    private var mapping: [String: String]          // "qt<id>" → id ThemeParks.wiki ("" = introuvable)
    private var loading: Set<Int64> = []

    private static let base = "https://api.themeparks.wiki/v1"
    private static let mappingCache = "tpw-mapping.json"

    init() {
        mapping = CacheStore.load([String: String].self, name: Self.mappingCache) ?? [:]
    }

    func schedule(for park: Park) -> ParkSchedule? {
        guard park.queueTimesID > 0 else { return nil }
        return schedules[park.queueTimesID] ?? CacheStore.load(ParkSchedule.self, name: "hours-\(park.queueTimesID).json")
    }

    /// Met à jour les horaires (au plus toutes les 6 h, sauf `force`).
    func refresh(parks: [Park], force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for park in parks where park.queueTimesID > 0 {
                let id = park.queueTimesID, name = park.wName, lat = park.latitude, lon = park.longitude
                group.addTask { await self.refresh(qtID: id, name: name, latitude: lat, longitude: lon, force: force) }
            }
        }
    }

    private func refresh(qtID: Int64, name: String, latitude: Double, longitude: Double, force: Bool) async {
        if loading.contains(qtID) { return }
        let cached = schedules[qtID] ?? CacheStore.load(ParkSchedule.self, name: "hours-\(qtID).json")
        if let cached, schedules[qtID] == nil { schedules[qtID] = cached }
        if !force, let cached, Date().timeIntervalSince(cached.fetchedAt) < 6 * 3600 { return }
        loading.insert(qtID)
        defer { loading.remove(qtID) }
        guard let tpwID = await resolve(qtID: qtID, name: name, latitude: latitude, longitude: longitude) else { return }
        do {
            let response = try await Network.get(TPWSchedule.self, from: "\(Self.base)/entity/\(tpwID)/schedule")
            let schedule = Self.build(response)
            schedules[qtID] = schedule
            CacheStore.save(schedule, name: "hours-\(qtID).json")
        } catch {
            // Hors ligne : on garde le cache.
        }
    }

    // MARK: Association Queue-Times → ThemeParks.wiki

    private func resolve(qtID: Int64, name: String, latitude: Double, longitude: Double) async -> String? {
        let key = "qt\(qtID)"
        if let known = mapping[key] { return known.isEmpty ? nil : known }
        guard let destinations = try? await Network.get(TPWDestinations.self, from: "\(Self.base)/destinations") else { return nil }
        let wanted = Self.tokens(name)
        guard !wanted.isEmpty else { return nil }
        let scored = destinations.destinations.flatMap { dest in
            dest.parks.map { park -> (id: String, score: Double) in
                let have = Self.tokens(park.name).union(Self.tokens(dest.name))
                return (park.id, Double(wanted.intersection(have).count) / Double(wanted.count))
            }
        }
        .filter { $0.score >= 0.34 }
        .sorted { $0.score > $1.score }
        .prefix(4)

        var found: String?
        if latitude != 0 || longitude != 0 {
            var best: (id: String, km: Double)?
            var reached = false
            for candidate in scored {
                guard let entity = try? await Network.get(TPWEntity.self, from: "\(Self.base)/entity/\(candidate.id)"),
                      let loc = entity.location, let lat = loc.latitude, let lon = loc.longitude else { continue }
                reached = true
                let km = QueueTimesService.distanceKm(latitude, longitude, lat, lon)
                if km < 25, km < (best?.km ?? .infinity) { best = (candidate.id, km) }
            }
            found = best?.id
            if !reached && !scored.isEmpty { return nil }   // hors ligne : on réessaiera
        } else if let first = scored.first, first.score >= 0.6, scored.dropFirst().first?.score != first.score {
            found = first.id
        }
        mapping[key] = found ?? ""
        CacheStore.save(mapping, name: Self.mappingCache)
        return found
    }

    nonisolated static func tokens(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["the", "park", "parc", "theme", "resort", "at", "of", "de", "la", "le", "and", "s", "disney", "universal", "water", "walt", "world"]
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let kept = words.filter { !ignored.contains($0) }
        return Set(kept.isEmpty ? words : kept)
    }

    // MARK: Lecture du planning

    nonisolated static func build(_ response: TPWSchedule) -> ParkSchedule {
        let iso = ISO8601DateFormatter()
        var byDay: [String: (open: Date?, close: Date?, extra: [ParkDayHours.Slot])] = [:]
        for entry in response.schedule ?? [] {
            guard let date = entry.date else { continue }
            var day = byDay[date] ?? (nil, nil, [])
            let open = entry.openingTime.flatMap { iso.date(from: $0) }
            let close = entry.closingTime.flatMap { iso.date(from: $0) }
            switch entry.type {
            case "OPERATING":
                if let open, let close {
                    day.open = min(day.open ?? open, open)
                    day.close = max(day.close ?? close, close)
                }
            case "EXTRA_HOURS":
                if let open, let close { day.extra.append(.init(open: open, close: close, label: entry.description ?? "Ouverture anticipée")) }
            case "TICKETED_EVENT":
                if let open, let close { day.extra.append(.init(open: open, close: close, label: entry.description ?? "Soirée spéciale (billet à part)")) }
            default:
                break
            }
            byDay[date] = day
        }
        let days = byDay.map { ParkDayHours(dayKey: $0.key, open: $0.value.open, close: $0.value.close,
                                            extra: $0.value.extra.sorted { $0.open < $1.open }) }
            .sorted { $0.dayKey < $1.dayKey }
        return ParkSchedule(timeZoneID: response.timezone ?? TimeZone.current.identifier, fetchedAt: Date(), days: days)
    }

    // MARK: Affichage

    /// « 9h – 20h », dans le fuseau du parc.
    nonisolated static func range(_ open: Date, _ close: Date, timeZone: TimeZone) -> String {
        "\(time(open, timeZone)) – \(time(close, timeZone))"
    }

    nonisolated static func time(_ date: Date, _ timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h)h" : String(format: "%dh%02d", h, m)
    }

    /// Clé du jour (yyyy-MM-dd) dans le fuseau du parc.
    nonisolated static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Réponses ThemeParks.wiki

struct TPWDestinations: Decodable {
    struct Destination: Decodable {
        struct ParkRef: Decodable { let id: String; let name: String }
        let id: String
        let name: String
        let parks: [ParkRef]
    }
    let destinations: [Destination]
}

struct TPWEntity: Decodable {
    struct Location: Decodable { let latitude: Double?; let longitude: Double? }
    let id: String
    let location: Location?
}

struct TPWSchedule: Decodable {
    struct Entry: Decodable {
        let date: String?
        let type: String?
        let description: String?
        let openingTime: String?
        let closingTime: String?
    }
    let timezone: String?
    let schedule: [Entry]?
}

// MARK: - Vues

/// Pastille « Ouvert · 9h – 20h » / « Fermé » / « Ouvre à 9h » pour aujourd'hui.
struct ParkHoursBadge: View {
    let schedule: ParkSchedule?
    var now: Date = Date()

    var body: some View {
        if let schedule, let day = schedule.day(ParkHoursService.dayKey(now, timeZone: schedule.timeZone)) {
            let tz = schedule.timeZone
            if let open = day.open, let close = day.close {
                let state: (String, Color) = now < open ? ("Ouvre à \(ParkHoursService.time(open, tz))", .orange)
                    : (now < close ? ("Ouvert", .green) : ("Fermé", .secondary))
                HStack(spacing: 4) {
                    Circle().fill(state.1).frame(width: 7, height: 7)
                    Text(state.0).fontWeight(.semibold)
                    Text("· \(ParkHoursService.range(open, close, timeZone: tz))").foregroundStyle(.secondary)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            } else {
                Label("Fermé aujourd'hui", systemImage: "moon.zzz").font(.caption).foregroundStyle(.secondary)
            }
        } else if schedule != nil {
            Text("Horaires du jour non publiés").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Section d'horaires : les jours du voyage publiés, sinon les 7 prochains jours.
struct ParkHoursList: View {
    let schedule: ParkSchedule?
    let tripDayKeys: [String]
    var tint: Color = .accentColor

    var body: some View {
        if let schedule {
            let tz = schedule.timeZone
            let today = ParkHoursService.dayKey(Date(), timeZone: tz)
            let tripDays = schedule.days.filter { tripDayKeys.contains($0.dayKey) && $0.dayKey >= today }
            let shown = tripDays.isEmpty ? Array(schedule.days.filter { $0.dayKey >= today }.prefix(7)) : tripDays
            if shown.isEmpty {
                Text("Horaires non disponibles pour le moment.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.dayKey) { day in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(Self.label(day.dayKey, today: today))
                            .fontWeight(day.dayKey == today ? .semibold : .regular)
                        Spacer()
                        if let open = day.open, let close = day.close {
                            Text(ParkHoursService.range(open, close, timeZone: tz)).monospacedDigit().fontWeight(.semibold)
                        } else {
                            Text("Fermé").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(day.extra, id: \.self) { slot in
                        Label("\(Self.frenchLabel(slot.label)) · \(ParkHoursService.range(slot.open, slot.close, timeZone: tz))", systemImage: "sparkle")
                            .font(.caption).foregroundStyle(tint)
                    }
                }
                .font(.subheadline)
            }
            if tripDays.isEmpty, let last = schedule.lastKey, let firstTrip = tripDayKeys.first, firstTrip > last {
                Text("Les horaires des jours de votre voyage sont publiés environ un mois à l'avance. Ci-dessus : les prochains jours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Heures locales du parc · source ThemeParks.wiki").font(.caption2).foregroundStyle(.tertiary)
        } else {
            Text("Horaires non disponibles pour ce parc.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    static func label(_ key: String, today: String) -> String {
        if key == today { return "Aujourd'hui" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let date = f.date(from: key) else { return key }
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date).capitalized(with: Locale(identifier: "fr_FR"))
    }

    static func frenchLabel(_ label: String) -> String {
        let l = label.lowercased()
        if l.contains("early") || l.contains("extra magic") || l.contains("early park admission") { return "Ouverture anticipée (hôtels)" }
        if l.contains("extended evening") { return "Soirée prolongée (hôtels)" }
        if l.contains("ticketed") || l.contains("party") || l.contains("halloween") || l.contains("christmas") { return "Soirée spéciale (billet à part)" }
        return label
    }
}
