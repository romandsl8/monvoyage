import Foundation
import CoreData
import UserNotifications

struct PlannedNotification: Equatable {
    var id: String
    var title: String
    var body: String
    var date: Date
}

/// Sélection pure (testable) : iOS limite à 64 notifications en attente → les plus proches d'abord.
enum NotificationPlanner {
    static let systemLimit = 64

    static func select(_ candidates: [PlannedNotification], now: Date = Date(), limit: Int = systemLimit) -> [PlannedNotification] {
        Array(candidates.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// 9 h du matin le jour donné (fuseau courant).
    static func morning(of date: Date, hour: Int = 9) -> Date {
        let cal = DayKey.calendar()
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = hour
        return cal.date(from: c) ?? date
    }
}

@MainActor
enum NotificationScheduler {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Toutes les notifications candidates, tous voyages non archivés confondus.
    static func candidates(context: NSManagedObjectContext, settings: AppSettings) -> [PlannedNotification] {
        var list: [PlannedNotification] = []
        let cal = DayKey.calendar()
        for trip in TripFactory.fetchTrips(in: context) {
            let tripName = trip.wName
            let tripID = trip.id?.uuidString ?? UUID().uuidString

            // Échéances de checklist
            for checklist in trip.checklistList {
                for item in checklist.itemList where !item.isDone {
                    guard let due = item.dueDate else { continue }
                    list.append(PlannedNotification(id: "check-\(item.id?.uuidString ?? "")", title: "À faire : \(item.title ?? "")",
                                                    body: "\(checklist.wTitle) — \(tripName)", date: NotificationPlanner.morning(of: due)))
                }
            }

            // Versements : 3 jours avant et le jour même
            for expense in trip.expenseList {
                for inst in expense.installmentList where !inst.isPaid {
                    guard let due = inst.dueDate else { continue }
                    let amount = Fmt.money(inst.amount, inst.currencyCode)
                    let base = inst.id?.uuidString ?? ""
                    if let before = cal.date(byAdding: .day, value: -3, to: due) {
                        list.append(PlannedNotification(id: "inst3-\(base)", title: "Échéance dans 3 jours",
                                                        body: "\(inst.kind.label) de \(amount) — \(expense.wTitle)", date: NotificationPlanner.morning(of: before)))
                    }
                    list.append(PlannedNotification(id: "inst0-\(base)", title: "Échéance aujourd'hui",
                                                    body: "\(inst.kind.label) de \(amount) — \(expense.wTitle)", date: NotificationPlanner.morning(of: due)))
                }
            }

            // Vols : enregistrement en ligne + départ pour l'aéroport
            for segment in trip.flightSegments {
                guard let departure = segment.departureDate else { continue }
                let base = segment.id?.uuidString ?? ""
                let flight = "\(segment.flightNumber ?? "") \(segment.routeText)"
                let checkIn = departure.addingTimeInterval(-Double(Airlines.checkInHours(for: segment.airlineCode)) * 3600)
                list.append(PlannedNotification(id: "checkin-\(base)", title: "Enregistrement en ligne ouvert",
                                                body: "\(flight) — \(segment.displayAirline)", date: checkIn))
                let leave = departure.addingTimeInterval(-Double(settings.airportLeadHours) * 3600)
                list.append(PlannedNotification(id: "leave-\(base)", title: "Départ pour l'aéroport",
                                                body: "\(flight) décolle à \(Fmt.time(departure, timeZone: segment.departureZone)) (heure locale)", date: leave))
            }

            // ESTA et passeports
            if let start = trip.startDate {
                for traveler in trip.travelerList {
                    if (traveler.estaNumber ?? "").isEmpty,
                       let remind = cal.date(byAdding: .day, value: -settings.estaReminderDays, to: start) {
                        list.append(PlannedNotification(id: "esta-\(traveler.id?.uuidString ?? "")-\(tripID)", title: "Pensez à l'ESTA",
                                                        body: "\(traveler.wName) n'a pas encore d'ESTA pour \(tripName).", date: NotificationPlanner.morning(of: remind)))
                    }
                    let end = trip.endDate ?? start
                    for (label, expiry) in [("Le passeport", traveler.passportExpiry), ("L'ESTA", traveler.estaExpiry)] {
                        guard let expiry, expiry < end, let remind = cal.date(byAdding: .day, value: -60, to: start) else { continue }
                        let date = max(NotificationPlanner.morning(of: remind), Date().addingTimeInterval(3600))
                        list.append(PlannedNotification(id: "expiry-\(label.hashValue)-\(traveler.id?.uuidString ?? "")", title: "Document expiré avant le retour",
                                                        body: "\(label) de \(traveler.wName) expire le \(Fmt.dateShort(expiry)).", date: date))
                    }
                }
            }

            // Rappels libres
            for reminder in trip.reminderList {
                guard let date = reminder.date else { continue }
                list.append(PlannedNotification(id: "rem-\(reminder.id?.uuidString ?? "")", title: reminder.title ?? "Rappel",
                                                body: tripName, date: date))
            }
        }
        return list
    }

    /// Reprogramme tout (appelé après chaque modification et au retour au premier plan).
    static func reschedule(context: NSManagedObjectContext, settings: AppSettings = .shared) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard settings.notificationsEnabled else { return }
        let selected = NotificationPlanner.select(candidates(context: context, settings: settings))
        for item in selected {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let comps = DayKey.calendar().dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
