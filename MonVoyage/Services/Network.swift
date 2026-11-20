import Foundation

/// Adresses des API gratuites, sans clé.
enum APIEndpoints {
    /// Frankfurter (taux BCE). Vérifié le 20/11/2026 : api.frankfurter.app redirige (301) vers api.frankfurter.dev/v1.
    static let frankfurter = "https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR"
    static let openMeteoForecast = "https://api.open-meteo.com/v1/forecast"
    static let openMeteoArchive = "https://archive-api.open-meteo.com/v1/archive"
    static let openMeteoGeocoding = "https://geocoding-api.open-meteo.com/v1/search"
    static let queueTimesParks = "https://queue-times.com/parks.json"
    static func queueTimes(parkID: Int64) -> String { "https://queue-times.com/parks/\(parkID)/queue_times.json" }
    static let queueTimesCredit = URL(string: "https://queue-times.com/")!
}

enum NetworkError: Error, LocalizedError {
    case badURL, badStatus(Int), invalidData
    var errorDescription: String? {
        switch self {
        case .badURL: return "Adresse invalide."
        case .badStatus(let code): return "Le serveur a répondu \(code)."
        case .invalidData: return "Données reçues invalides."
        }
    }
}

enum Network {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func get<T: Decodable>(_ type: T.Type, from urlString: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await getData(urlString, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.invalidData
        }
    }

    static func getData(_ urlString: String, query: [URLQueryItem] = []) async throws -> Data {
        guard var components = URLComponents(string: urlString) else { throw NetworkError.badURL }
        if !query.isEmpty { components.queryItems = (components.queryItems ?? []) + query }
        guard let url = components.url else { throw NetworkError.badURL }
        var request = URLRequest(url: url)
        request.setValue("MonVoyage-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NetworkError.badStatus(http.statusCode)
        }
        return data
    }
}

/// Caches JSON dans le conteneur App Group (lisibles par le widget).
enum CacheStore {
    static var directory: URL {
        let url = AppGroup.containerURL.appendingPathComponent("Caches", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
