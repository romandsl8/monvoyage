import Foundation
import Combine

struct DayWeather: Codable, Equatable {
    var tMin: Double
    var tMax: Double
    var precipitation: Double
    var precipitationProbability: Int?
    var code: Int
    /// true = « normale » (même date l'année précédente)
    var isNormal: Bool

    var symbol: String { WeatherLogic.symbol(for: code) }
    var label: String { WeatherLogic.label(for: code) }
}

struct TripWeatherCache: Codable {
    var updatedAt: Date
    var latitude: Double
    var longitude: Double
    /// clé "yyyy-MM-dd" du jour du voyage → météo
    var days: [String: DayWeather]
}

struct GeocodingResult: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let country: String?
    let admin1: String?
    let country_code: String?

    var subtitle: String { [admin1, country].compactMap { $0 }.joined(separator: ", ") }
}

/// Météo Open-Meteo : prévision ≤ 16 jours, sinon normales (archive de l'année précédente).
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    static let refreshInterval: TimeInterval = 3 * 3600

    @Published private(set) var caches: [String: TripWeatherCache] = [:]

    private func cacheName(_ tripKey: String) -> String { "weather-\(tripKey).json" }

    /// Lecture disque non publiée (appelable pendant le rendu d'une vue).
    private var diskCache: [String: TripWeatherCache] = [:]

    private func cached(_ tripKey: String) -> TripWeatherCache? {
        if let c = caches[tripKey] { return c }
        if let c = diskCache[tripKey] { return c }
        let loaded = CacheStore.load(TripWeatherCache.self, name: cacheName(tripKey))
        if let loaded { diskCache[tripKey] = loaded }
        return loaded
    }

    func weather(tripKey: String, dayKey: String) -> DayWeather? {
        cached(tripKey)?.days[dayKey]
    }

    func updatedAt(tripKey: String) -> Date? {
        cached(tripKey)?.updatedAt
    }

    func refresh(tripKey: String, latitude: Double, longitude: Double, dayKeys: [String], force: Bool = false) async {
        guard !dayKeys.isEmpty, latitude != 0 || longitude != 0 else { return }
        var cache = caches[tripKey] ?? CacheStore.load(TripWeatherCache.self, name: cacheName(tripKey))
        if !force, let c = cache, Date().timeIntervalSince(c.updatedAt) < Self.refreshInterval,
           c.latitude == latitude, c.longitude == longitude,
           dayKeys.allSatisfy({ c.days[$0] != nil }) {
            caches[tripKey] = c
            return
        }
        var result = (cache?.latitude == latitude && cache?.longitude == longitude) ? (cache?.days ?? [:]) : [:]

        var forecastKeys: [String] = []
        var normalPairs: [(day: String, source: String)] = []
        for key in dayKeys {
            switch WeatherLogic.source(for: key) {
            case .forecast: forecastKeys.append(key)
            case .normals(let previous): normalPairs.append((key, previous))
            }
        }

        if !forecastKeys.isEmpty, let forecast = try? await fetchForecast(latitude: latitude, longitude: longitude) {
            for key in forecastKeys { if let w = forecast[key] { result[key] = w } }
        }
        if let first = normalPairs.map(\.source).min(), let last = normalPairs.map(\.source).max(),
           let archive = try? await fetchArchive(latitude: latitude, longitude: longitude, start: first, end: last) {
            for pair in normalPairs {
                if var w = archive[pair.source] { w.isNormal = true; result[pair.day] = w }
            }
        }
        guard !result.isEmpty else { return }
        cache = TripWeatherCache(updatedAt: Date(), latitude: latitude, longitude: longitude, days: result)
        caches[tripKey] = cache
        CacheStore.save(cache!, name: cacheName(tripKey))
    }

    private struct DailyResponse: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]?
            let temperature_2m_max: [Double?]?
            let temperature_2m_min: [Double?]?
            let precipitation_sum: [Double?]?
            let precipitation_probability_max: [Int?]?
        }
        let daily: Daily?
    }

    private func parse(_ response: DailyResponse, isNormal: Bool) -> [String: DayWeather] {
        guard let d = response.daily else { return [:] }
        var out: [String: DayWeather] = [:]
        for (i, key) in d.time.enumerated() {
            guard let tMax = d.temperature_2m_max?[safe: i] ?? nil,
                  let tMin = d.temperature_2m_min?[safe: i] ?? nil else { continue }
            out[key] = DayWeather(tMin: tMin, tMax: tMax,
                                  precipitation: (d.precipitation_sum?[safe: i] ?? nil) ?? 0,
                                  precipitationProbability: d.precipitation_probability_max?[safe: i] ?? nil,
                                  code: (d.weather_code?[safe: i] ?? nil) ?? 2,
                                  isNormal: isNormal)
        }
        return out
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> [String: DayWeather] {
        let response = try await Network.get(DailyResponse.self, from: APIEndpoints.openMeteoForecast, query: [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "past_days", value: "2"),
            URLQueryItem(name: "forecast_days", value: "16")
        ])
        return parse(response, isNormal: false)
    }

    private func fetchArchive(latitude: Double, longitude: Double, start: String, end: String) async throws -> [String: DayWeather] {
        let response = try await Network.get(DailyResponse.self, from: APIEndpoints.openMeteoArchive, query: [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum"),
            URLQueryItem(name: "timezone", value: "auto")
        ])
        return parse(response, isNormal: true)
    }

    /// Géocodage d'une ville (coordonnées + fuseau horaire).
    static func searchCity(_ name: String) async throws -> [GeocodingResult] {
        struct Response: Decodable { let results: [GeocodingResult]? }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let response = try await Network.get(Response.self, from: APIEndpoints.openMeteoGeocoding, query: [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "fr"),
            URLQueryItem(name: "format", value: "json")
        ])
        return response.results ?? []
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
