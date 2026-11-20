import Foundation
import Combine

// MARK: - Queue-Times (attractions et temps d'attente)

struct QTPark: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let latitude: String?
    let longitude: String?
    let timezone: String?
}

struct QTCompany: Codable {
    let id: Int64
    let name: String
    let parks: [QTPark]
}

struct QTRide: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let is_open: Bool?
    let wait_time: Int?
    let last_updated: String?
}

struct QTLand: Codable, Identifiable {
    let id: Int64
    let name: String
    let rides: [QTRide]
}

struct QTQueueResponse: Codable {
    let lands: [QTLand]?
    let rides: [QTRide]?
}

struct WaitTimesCache: Codable {
    var updatedAt: Date
    var rides: [Int64: Int]       // id → minutes
    var open: [Int64: Bool]
}

/// Parcs proposés par défaut (ids Queue-Times vérifiés le 20/11/2026, revérifiés via parks.json).
enum DefaultParks {
    static let names: [(name: String, fallbackID: Int64, match: String)] = [
        ("Universal Studios Florida", 65, "Universal Studios At Universal Orlando"),
        ("Islands of Adventure", 64, "Islands Of Adventure"),
        ("Epic Universe", 334, "Epic Universe"),
        ("Volcano Bay", 67, "Volcano Bay")
    ]
}

@MainActor
final class QueueTimesService: ObservableObject {
    static let shared = QueueTimesService()

    @Published private(set) var parks: [QTPark] = []
    @Published private(set) var waitTimes: [Int64: WaitTimesCache] = [:]
    @Published private(set) var lastError: String?

    private static let parksCache = "queuetimes-parks.json"

    init() {
        parks = CacheStore.load([QTPark].self, name: Self.parksCache) ?? []
    }

    func loadParks(force: Bool = false) async {
        if !parks.isEmpty && !force { return }
        do {
            let companies = try await Network.get([QTCompany].self, from: APIEndpoints.queueTimesParks)
            let all = companies.flatMap(\.parks).sorted { $0.name < $1.name }
            parks = all
            CacheStore.save(all, name: Self.parksCache)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Id Queue-Times d'un parc par défaut (via parks.json si disponible).
    func resolveID(match: String, fallback: Int64) -> Int64 {
        parks.first { $0.name.localizedCaseInsensitiveContains(match) }?.id ?? fallback
    }

    /// Liste des attractions (pour l'import d'un appui).
    func fetchRides(parkID: Int64) async throws -> [(area: String, ride: QTRide)] {
        let response = try await Network.get(QTQueueResponse.self, from: APIEndpoints.queueTimes(parkID: parkID))
        var result: [(area: String, ride: QTRide)] = []
        for land in response.lands ?? [] { for ride in land.rides { result.append((area: land.name, ride: ride)) } }
        for ride in response.rides ?? [] { result.append((area: "Autres", ride: ride)) }
        return result
    }

    func cachedWaits(parkID: Int64) -> WaitTimesCache? {
        waitTimes[parkID] ?? CacheStore.load(WaitTimesCache.self, name: "waits-\(parkID).json")
    }

    /// Temps d'attente en direct : appelé uniquement quand l'écran est visible.
    func refreshWaits(parkID: Int64) async {
        do {
            let rides = try await fetchRides(parkID: parkID)
            var waits: [Int64: Int] = [:]
            var open: [Int64: Bool] = [:]
            for (_, ride) in rides {
                waits[ride.id] = ride.wait_time ?? 0
                open[ride.id] = ride.is_open ?? false
            }
            let cache = WaitTimesCache(updatedAt: Date(), rides: waits, open: open)
            waitTimes[parkID] = cache
            CacheStore.save(cache, name: "waits-\(parkID).json")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if waitTimes[parkID] == nil, let cached = CacheStore.load(WaitTimesCache.self, name: "waits-\(parkID).json") {
                waitTimes[parkID] = cached
            }
        }
    }
}

// MARK: - Affluence (fichier affluence.json publié par GitHub Actions)

struct AffluenceDay: Codable, Equatable {
    var level: Int?
    var label: String?
    var open: String?
    var close: String?
}

struct AffluenceFile: Codable, Equatable {
    var updatedAt: String
    var source: String
    /// parkId (Queue-Times) → "yyyy-MM-dd" → jour
    var parks: [String: [String: AffluenceDay]]
}

struct AffluenceCache: Codable {
    var fetchedAt: Date
    var file: AffluenceFile
}

/// Résultat affiché pour un parc et un jour.
struct CrowdInfo: Equatable {
    var level: Int?
    var label: String?
    var open: String?
    var close: String?
    var source: String
    var updatedAt: Date?
    var isManual: Bool
}

@MainActor
final class AffluenceService: ObservableObject {
    static let shared = AffluenceService()
    static let urlKey = "affluenceURL"
    static let defaultURL = "https://VOTRE-COMPTE.github.io/monvoyage-data/affluence.json"
    private static let cacheName = "affluence.json"

    @Published private(set) var cache: AffluenceCache?
    @Published private(set) var lastError: String?
    @Published var urlString: String {
        didSet { AppGroup.defaults.set(urlString, forKey: Self.urlKey) }
    }

    init() {
        urlString = AppGroup.defaults.string(forKey: Self.urlKey) ?? Self.defaultURL
        cache = CacheStore.load(AffluenceCache.self, name: Self.cacheName)
    }

    func refresh(force: Bool = false) async {
        if !force, let cache, Date().timeIntervalSince(cache.fetchedAt) < 6 * 3600 { return }
        guard !urlString.contains("VOTRE-COMPTE") else {
            lastError = "Adresse du fichier d'affluence à renseigner dans les Réglages."
            return
        }
        do {
            let data = try await Network.getData(urlString)
            let file = try JSONDecoder().decode(AffluenceFile.self, from: data)
            let newCache = AffluenceCache(fetchedAt: Date(), file: file)
            cache = newCache
            CacheStore.save(newCache, name: Self.cacheName)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saisie manuelle prioritaire, sinon fichier publié.
    func info(park: Park, dayKey: String) -> CrowdInfo? {
        let crowdOverride = (park.crowdOverrides?.allObjects as? [CrowdOverride] ?? [])
            .first { $0.date.map { DayKey.key($0) } == dayKey }
        let hoursOverride = (park.hoursOverrides?.allObjects as? [ParkHoursOverride] ?? [])
            .first { $0.date.map { DayKey.key($0) } == dayKey }
        let fileDay = cache?.file.parks[String(park.queueTimesID)]?[dayKey]

        if crowdOverride == nil && hoursOverride == nil && fileDay == nil { return nil }
        var info = CrowdInfo(level: fileDay?.level, label: fileDay?.label, open: fileDay?.open, close: fileDay?.close,
                             source: cache?.file.source ?? "", updatedAt: cache?.fetchedAt, isManual: false)
        if let crowdOverride {
            info.level = Int(crowdOverride.level)
            info.label = crowdOverride.label
            info.isManual = true
            info.source = "Saisie manuelle"
            info.updatedAt = crowdOverride.updatedAt
        }
        if let hoursOverride {
            info.open = hoursOverride.openTime
            info.close = hoursOverride.closeTime
        }
        if info.label == nil, let level = info.level { info.label = CrowdScale.label(for: level) }
        return info
    }
}
