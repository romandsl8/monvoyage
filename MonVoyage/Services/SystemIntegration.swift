import Foundation
import CoreData
import WidgetKit
import BackgroundTasks

// MARK: - Widget

@MainActor
enum WidgetSnapshotWriter {
    static func update(context: NSManagedObjectContext, now: Date = Date()) {
        guard let trip = TripFactory.currentOrNextTrip(in: context, now: now),
              let start = trip.startDate, let end = trip.endDate else {
            WidgetSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        // Pas de budget défini → pas de « 0 € » rouge dans le widget.
        let daily = BudgetSummary.onSiteBudget(trip: trip) > 0 ? BudgetSummary.daily(trip: trip, now: now) : nil
        let rate = ExchangeRateService.shared.usdToEUR
        let next = trip.activityList.first { ($0.time ?? .distantPast) > now }
        let snapshot = WidgetSnapshot(
            tripName: trip.wName, city: trip.city ?? "", accentHex: trip.accentHex ?? "#3A7BFF",
            startDate: start, endDate: end,
            firstDeparture: trip.flightSegments.first(where: { ($0.departureDate ?? .distantPast) > now })?.departureDate ?? trip.firstDeparture,
            dailyBudgetEUR: daily?.perDayEUR,
            dailyBudgetUSD: daily.map { Money.fromEUR($0.perDayEUR, currency: "USD", rateEURPerUnit: rate) },
            spentTodayEUR: daily?.spentTodayEUR ?? 0, budgetStatus: daily?.status ?? 0,
            nextActivityTitle: next?.wTitle, nextActivityDate: next?.time, updatedAt: now)
        // On ne recharge les widgets que si le contenu a changé (budget de rechargements limité par iOS).
        if let previous = WidgetSnapshot.load() {
            var comparable = snapshot
            comparable.updatedAt = previous.updatedAt
            if comparable == previous { return }
        }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Tâche de fond

enum BackgroundRefresh {
    static var taskID: String { (Bundle.main.bundleIdentifier ?? "fr.tanguy.monvoyage") + ".refresh" }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Rafraîchit taux, affluence, météo du voyage en cours, puis le widget.
    @MainActor
    static func run() async {
        schedule()
        let context = PersistenceController.shared.viewContext
        await ExchangeRateService.shared.refreshIfNeeded()
        await AffluenceService.shared.refresh()
        if let trip = TripFactory.currentOrNextTrip(in: context), let id = trip.id?.uuidString {
            await WeatherService.shared.refresh(tripKey: id, latitude: trip.latitude, longitude: trip.longitude, dayKeys: trip.dayKeys)
        }
        WidgetSnapshotWriter.update(context: context)
    }
}
