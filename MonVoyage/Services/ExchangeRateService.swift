import Foundation
import Combine

/// Taux USD → EUR (Frankfurter), au plus une fois par jour, avec repli et forçage manuel.
@MainActor
final class ExchangeRateService: ObservableObject {
    static let shared = ExchangeRateService()

    struct Cache: Codable {
        var rate: Double
        var fetchedAt: Date
        var sourceDate: String?
    }

    /// Taux par défaut si rien n'a jamais été récupéré (à corriger dans les Réglages).
    static let fallbackRate = 0.92
    private static let manualKey = "manualUSDRate"
    private static let cacheName = "rate-usd-eur.json"

    @Published private(set) var cache: Cache?
    @Published var manualRate: Double? {
        didSet {
            if let manualRate { UserDefaults.standard.set(manualRate, forKey: Self.manualKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.manualKey) }
        }
    }
    @Published private(set) var lastError: String?

    init() {
        cache = CacheStore.load(Cache.self, name: Self.cacheName)
        let stored = UserDefaults.standard.double(forKey: Self.manualKey)
        manualRate = stored > 0 ? stored : nil
    }

    /// EUR pour 1 USD.
    var usdToEUR: Double { manualRate ?? cache?.rate ?? Self.fallbackRate }
    var isManual: Bool { manualRate != nil }
    var updatedAt: Date? { cache?.fetchedAt }

    func rate(for currency: String) -> Double {
        currency.uppercased() == "EUR" ? 1 : usdToEUR
    }

    func toEUR(_ amount: Double, currency: String) -> Double {
        Money.toEUR(amount, currency: currency, rateEURPerUnit: rate(for: currency))
    }

    func refreshIfNeeded(force: Bool = false) async {
        if !force, let cache, Calendar.current.isDateInToday(cache.fetchedAt) { return }
        struct Response: Decodable { let date: String?; let rates: [String: Double] }
        do {
            let response = try await Network.get(Response.self, from: APIEndpoints.frankfurter)
            guard let eur = response.rates["EUR"], eur > 0 else { throw NetworkError.invalidData }
            let newCache = Cache(rate: eur, fetchedAt: Date(), sourceDate: response.date)
            cache = newCache
            CacheStore.save(newCache, name: Self.cacheName)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
