import Foundation
import CoreData
import WidgetKit
import ActivityKit
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
        let daily = BudgetSummary.daily(trip: trip, now: now)
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

// MARK: - Live Activity

@MainActor
enum LiveActivityManager {
    /// Démarre (ou met à jour) la Live Activity du jour : vol, sinon jour de parc.
    static func refresh(context: NSManagedObjectContext, now: Date = Date()) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let trip = TripFactory.currentOrNextTrip(in: context, now: now) else { return }
        guard let state = state(for: trip, now: now) else {
            await endAll()
            return
        }
        let endOfDay = DayKey.endOfDay(now)
        let content = ActivityContent(state: state, staleDate: endOfDay)
        if let existing = Activity<TripActivityAttributes>.activities.first {
            await existing.update(content)
            return
        }
        let attributes = TripActivityAttributes(tripName: trip.wName, accentHex: trip.accentHex ?? "#3A7BFF")
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("Live Activity impossible : \(error)")
        }
    }

    static func state(for trip: Trip, now: Date) -> TripActivityAttributes.ContentState? {
        let todayKey = DayKey.key(now)
        if let flight = trip.flightSegments.first(where: { seg in
            guard let dep = seg.departureDate else { return false }
            return dep > now && DayKey.key(dep) == todayKey
        }), let dep = flight.departureDate {
            let detail = [flight.terminal.map { "Terminal \($0)" }, flight.seat.map { "Siège \($0)" }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return .init(kind: "flight", title: "\(flight.flightNumber ?? "Vol") \(flight.routeText)",
                         subtitle: "Décollage \(Fmt.time(dep, timeZone: flight.departureZone))", targetDate: dep,
                         detail: detail.isEmpty ? flight.displayAirline : detail)
        }
        if !trip.parks(on: todayKey).isEmpty,
           let next = trip.activities(on: todayKey).first(where: { ($0.time ?? .distantPast) > now }), let time = next.time {
            return .init(kind: "park", title: next.wTitle, subtitle: "À \(Fmt.time(time, timeZone: trip.tripTimeZone))",
                         targetDate: time, detail: next.place ?? "")
        }
        return nil
    }

    static func endAll() async {
        for activity in Activity<TripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
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
