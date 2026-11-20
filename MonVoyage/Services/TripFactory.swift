import Foundation
import CoreData

/// Création des voyages et des éléments par défaut.
enum TripFactory {
    static let defaultCategories: [(name: String, symbol: String, preDeparture: Bool)] = [
        ("Vols", "airplane", true),
        ("Hébergement", "bed.double.fill", true),
        ("Billets parcs", "ticket.fill", true),
        ("Express Pass", "bolt.fill", true),
        ("Repas", "fork.knife", false),
        ("Transport", "car.fill", false),
        ("Shopping", "bag.fill", false),
        ("Souvenirs", "gift.fill", false),
        ("Divers", "ellipsis.circle.fill", false)
    ]

    @discardableResult
    static func createTrip(in context: NSManagedObjectContext, name: String = "", start: Date = Date(), end: Date = Date().addingTimeInterval(7 * 86400)) -> Trip {
        let trip = context.make(Trip.self, trip: nil)
        trip.name = name
        trip.startDate = DayKey.noon(start)
        trip.endDate = DayKey.noon(end)
        trip.accentHex = AccentPalette.colors.randomElement() ?? "#3A7BFF"
        trip.localCurrency = "USD"
        trip.taxRate = 0.065
        trip.defaultTipRate = 0.20
        for (index, item) in defaultCategories.enumerated() {
            let cat = context.make(BudgetCategory.self, trip: trip)
            cat.name = item.name
            cat.symbol = item.symbol
            cat.isPreDeparture = item.preDeparture
            cat.sortIndex = Int32(index)
            cat.trip = trip
        }
        for index in 0..<2 {
            let traveler = context.make(Traveler.self, trip: trip)
            traveler.name = "Voyageur \(index + 1)"
            traveler.sortIndex = Int32(index)
            traveler.trip = trip
        }
        return trip
    }

    /// Ajoute les parcs de départ (Universal Orlando) au voyage.
    @MainActor
    static func addDefaultParks(to trip: Trip, in context: NSManagedObjectContext) {
        let existing = Set(trip.parkList.map(\.queueTimesID))
        let service = QueueTimesService.shared
        var index = Int32(trip.parkList.count)
        for item in DefaultParks.names {
            let id = service.resolveID(match: item.match, fallback: item.fallbackID)
            guard !existing.contains(id) else { continue }
            let park = context.make(Park.self, trip: trip)
            park.name = item.name
            park.queueTimesID = id
            park.sortIndex = index
            if let qt = service.parks.first(where: { $0.id == id }) {
                park.latitude = Double(qt.latitude ?? "") ?? 0
                park.longitude = Double(qt.longitude ?? "") ?? 0
            }
            park.trip = trip
            index += 1
        }
    }

    static func fetchTrips(in context: NSManagedObjectContext, includeArchived: Bool = false) -> [Trip] {
        let request = NSFetchRequest<Trip>(entityName: "Trip")
        if !includeArchived { request.predicate = NSPredicate(format: "archived == NO") }
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Voyage en cours, sinon le prochain à venir.
    static func currentOrNextTrip(in context: NSManagedObjectContext, now: Date = Date()) -> Trip? {
        let trips = fetchTrips(in: context)
        if let ongoing = trips.first(where: { $0.isOngoing(now: now) }) { return ongoing }
        return trips.filter { $0.isUpcoming(now: now) }.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
}
