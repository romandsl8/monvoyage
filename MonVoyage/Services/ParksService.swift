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

struct QTCompany: Codable, Identifiable {
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
@MainActor
final class QueueTimesService: ObservableObject {
    static let shared = QueueTimesService()

    @Published private(set) var parks: [QTPark] = []
    @Published private(set) var waitTimes: [Int64: WaitTimesCache] = [:]
    @Published private(set) var lastError: String?

    /// Parcs regroupés par exploitant (Disney, Universal, Six Flags…).
    @Published private(set) var companies: [QTCompany] = []

    private static let parksCache = "queuetimes-parks.json"
    private static let companiesCache = "queuetimes-companies.json"

    init() {
        parks = CacheStore.load([QTPark].self, name: Self.parksCache) ?? []
        companies = CacheStore.load([QTCompany].self, name: Self.companiesCache) ?? []
    }

    func loadParks(force: Bool = false) async {
        if !parks.isEmpty && !companies.isEmpty && !force { return }
        do {
            let loaded = try await Network.get([QTCompany].self, from: APIEndpoints.queueTimesParks)
            let all = loaded.flatMap(\.parks).sorted { $0.name < $1.name }
            parks = all
            companies = loaded.filter { !$0.parks.isEmpty }
                .map { QTCompany(id: $0.id, name: $0.name, parks: $0.parks.sorted { $0.name < $1.name }) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            CacheStore.save(all, name: Self.parksCache)
            CacheStore.save(companies, name: Self.companiesCache)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Parcs du même complexe : même groupe et à moins de 12 km
    /// (ex. Disneyland Park et Disney Adventure World à Paris, les parcs Universal Orlando).
    func siblings(of park: QTPark) -> [QTPark] {
        guard let company = companies.first(where: { $0.parks.contains { $0.id == park.id } }),
              let lat = Double(park.latitude ?? ""), let lon = Double(park.longitude ?? "") else { return [] }
        return company.parks.filter { other in
            guard other.id != park.id, let olat = Double(other.latitude ?? ""), let olon = Double(other.longitude ?? "") else { return false }
            return Self.distanceKm(lat, lon, olat, olon) < 12
        }
    }

    nonisolated static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
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
            var live: [LiveRide] = []
            for (area, ride) in rides {
                waits[ride.id] = ride.wait_time ?? 0
                open[ride.id] = ride.is_open ?? false
                live.append(LiveRide(id: ride.id, parkID: parkID, name: ride.name, land: area,
                                     wait: ride.wait_time ?? 0, isOpen: ride.is_open ?? false, lastUpdated: ride.last_updated))
            }
            let cache = WaitTimesCache(updatedAt: Date(), rides: waits, open: open)
            waitTimes[parkID] = cache
            CacheStore.save(cache, name: "waits-\(parkID).json")
            let board = LiveParkWaits(updatedAt: Date(), rides: live)
            liveRides[parkID] = board
            CacheStore.save(board, name: "live-\(parkID).json")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if waitTimes[parkID] == nil, let cached = CacheStore.load(WaitTimesCache.self, name: "waits-\(parkID).json") {
                waitTimes[parkID] = cached
            }
            if liveRides[parkID] == nil, let cached = CacheStore.load(LiveParkWaits.self, name: "live-\(parkID).json") {
                liveRides[parkID] = cached
            }
        }
    }

    /// Toutes les attractions en direct d'un parc (dernier relevé connu).
    @Published private(set) var liveRides: [Int64: LiveParkWaits] = [:]

    func cachedLive(parkID: Int64) -> LiveParkWaits? {
        liveRides[parkID] ?? CacheStore.load(LiveParkWaits.self, name: "live-\(parkID).json")
    }

    /// Rafraîchit plusieurs parcs en parallèle.
    func refreshWaits(parkIDs: [Int64]) async {
        await withTaskGroup(of: Void.self) { group in
            for id in Set(parkIDs) where id > 0 {
                group.addTask { await self.refreshWaits(parkID: id) }
            }
        }
    }
}

/// Une attraction et son temps d'attente en direct (Queue-Times).
struct LiveRide: Codable, Identifiable, Hashable {
    let id: Int64
    let parkID: Int64
    let name: String
    let land: String
    let wait: Int
    let isOpen: Bool
    let lastUpdated: String?
}

struct LiveParkWaits: Codable {
    var updatedAt: Date
    var rides: [LiveRide]
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
