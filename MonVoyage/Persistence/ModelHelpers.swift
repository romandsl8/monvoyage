import Foundation
import CoreData
import SwiftUI

// MARK: - Énumérations stockées en entiers

enum InstallmentKind: Int16, CaseIterable, Identifiable {
    case deposit = 0, installment = 1
    var id: Int16 { rawValue }
    var label: String { self == .deposit ? "Acompte" : "Versement" }
}

/// Moment d'une dépense par rapport au voyage (attribut `phaseRaw`, modèle v2).
enum ExpensePhase: Int16, CaseIterable, Identifiable {
    /// Anciennes dépenses : déduit de la catégorie (« avant départ »).
    case auto = 0
    case beforeTrip = 1
    case duringTrip = 2
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .auto: return "Selon la catégorie"
        case .beforeTrip: return "Avant le voyage"
        case .duringTrip: return "Pendant le voyage"
        }
    }

    /// Valeur proposée par défaut : catégorie « avant départ » ou date antérieure au voyage → avant.
    static func suggested(category: BudgetCategory?, date: Date?, trip: Trip) -> ExpensePhase {
        if category?.isPreDeparture == true { return .beforeTrip }
        if let date, let start = trip.startDate, DayKey.key(date) < DayKey.key(start) { return .beforeTrip }
        if category == nil, date == nil { return .beforeTrip }
        return .duringTrip
    }
}

enum ActivityKind: Int16, CaseIterable, Identifiable {
    case park = 0, attraction, restaurant, transport, flight, other
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .park: return "Parc"
        case .attraction: return "Attraction"
        case .restaurant: return "Restaurant"
        case .transport: return "Transport"
        case .flight: return "Vol"
        case .other: return "Autre"
        }
    }
    var symbol: String {
        switch self {
        case .park: return "sparkles"
        case .attraction: return "figure.roll"
        case .restaurant: return "fork.knife"
        case .transport: return "car.fill"
        case .flight: return "airplane"
        case .other: return "star.fill"
        }
    }
}

enum ReservationKind: Int16, CaseIterable, Identifiable {
    case flight = 0, hotel, parkTicket, rental, restaurant, insurance, esta, other
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .flight: return "Vol"
        case .hotel: return "Hôtel"
        case .parkTicket: return "Billet parc"
        case .rental: return "Location"
        case .restaurant: return "Restaurant"
        case .insurance: return "Assurance"
        case .esta: return "ESTA"
        case .other: return "Autre"
        }
    }
    var symbol: String {
        switch self {
        case .flight: return "airplane"
        case .hotel: return "bed.double.fill"
        case .parkTicket: return "ticket.fill"
        case .rental: return "car.fill"
        case .restaurant: return "fork.knife"
        case .insurance: return "cross.case.fill"
        case .esta: return "doc.text.fill"
        case .other: return "folder.fill"
        }
    }
}

enum AttractionPriority: Int16, CaseIterable, Identifiable {
    case mustDo = 0, ifPossible = 1, optional = 2
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .mustDo: return "Incontournable"
        case .ifPossible: return "Si possible"
        case .optional: return "Facultatif"
        }
    }
    var color: Color {
        switch self {
        case .mustDo: return .pink
        case .ifPossible: return .orange
        case .optional: return .secondary
        }
    }
}

// MARK: - Helpers génériques

func sortedSet<T: NSManagedObject>(_ set: NSSet?, _ areInIncreasingOrder: (T, T) -> Bool) -> [T] {
    ((set?.allObjects as? [T]) ?? []).sorted(by: areInIncreasingOrder)
}

// MARK: - Trip

extension Trip {
    var wName: String { (name?.isEmpty == false ? name : nil) ?? "Voyage sans nom" }
    var accent: Color { Color(hex: accentHex) }
    var tripTimeZone: TimeZone { TimeZone(identifier: timeZoneID ?? "") ?? .current }
    var currencyCode: String { localCurrency ?? "USD" }

    var travelerList: [Traveler] { sortedSet(travelers) { $0.sortIndex < $1.sortIndex } }
    var categoryList: [BudgetCategory] { sortedSet(categories) { $0.sortIndex < $1.sortIndex } }
    var expenseList: [Expense] { sortedSet(expenses) { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } }
    var checklistList: [Checklist] { sortedSet(checklists) { $0.sortIndex < $1.sortIndex } }
    var activityList: [PlanActivity] { sortedSet(activities) { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) } }
    var reservationList: [Reservation] { sortedSet(reservations) { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) } }
    var parkList: [Park] { sortedSet(parks) { $0.sortIndex < $1.sortIndex } }
    var reminderList: [Reminder] { sortedSet(reminders) { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) } }
    var crowdOverrideList: [CrowdOverride] { sortedSet(crowdOverrides) { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) } }
    var hoursOverrideList: [ParkHoursOverride] { sortedSet(hoursOverrides) { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) } }

    var flightSegments: [FlightSegment] {
        reservationList.flatMap { $0.segmentList }
            .sorted { ($0.departureDate ?? .distantFuture) < ($1.departureDate ?? .distantFuture) }
    }

    /// Premier décollage à venir (sinon premier vol tout court).
    var firstDeparture: Date? { flightSegments.first?.departureDate }

    /// Fin du voyage = dernier jour (ou dernière arrivée).
    var returnDate: Date? { endDate }

    /// Jours du voyage (dates normalisées à midi).
    var days: [Date] {
        guard let startDate, let endDate else { return [] }
        return DayKey.days(from: startDate, to: endDate)
    }

    var dayKeys: [String] { days.map { DayKey.key($0) } }

    func isOngoing(now: Date = Date()) -> Bool {
        guard let startDate, let endDate else { return false }
        let today = DayKey.key(now)
        return DayKey.key(startDate) <= today && today <= DayKey.key(endDate)
    }

    func isUpcoming(now: Date = Date()) -> Bool {
        guard let startDate else { return false }
        return DayKey.key(startDate) > DayKey.key(now)
    }

    func isFinished(now: Date = Date()) -> Bool {
        guard let endDate else { return false }
        return DayKey.key(endDate) < DayKey.key(now)
    }

    /// Jours restants avant le départ (compte à rebours).
    func daysUntilDeparture(now: Date = Date()) -> Int? {
        guard let target = firstDeparture ?? startDate else { return nil }
        return DayMath.daysBetween(now, target)
    }

    func category(named name: String) -> BudgetCategory? {
        categoryList.first { ($0.name ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func activities(on dayKey: String) -> [PlanActivity] {
        activityList.filter { $0.dayKey == dayKey }
    }

    func expenses(on dayKey: String) -> [Expense] {
        expenseList.filter { $0.date.map { DayKey.key($0) } == dayKey }
    }

    func flights(on dayKey: String) -> [FlightSegment] {
        flightSegments.filter { $0.departureDayKey == dayKey }
    }

    /// Parcs prévus ce jour-là (activités de type parc reliées à un parc).
    func parks(on dayKey: String) -> [Park] {
        var result: [Park] = []
        for activity in activities(on: dayKey) {
            if let park = activity.park, !result.contains(park) { result.append(park) }
        }
        for park in parkList where park.attractionList.contains(where: { $0.assignedDay.map { DayKey.key($0) } == dayKey }) {
            if !result.contains(park) { result.append(park) }
        }
        return result
    }
}

// MARK: - Expense

extension Expense {
    var wTitle: String { (title?.isEmpty == false ? title : nil) ?? (merchant ?? "Dépense") }
    var currencyCode: String { currency ?? "EUR" }

    var phase: ExpensePhase { ExpensePhase(rawValue: phaseRaw) ?? .auto }

    /// Dépense réglée avant le voyage (exclue du budget sur place).
    var isPreTrip: Bool {
        switch phase {
        case .beforeTrip: return true
        case .duringTrip: return false
        case .auto: return category?.isPreDeparture == true
        }
    }

    var installmentList: [PaymentInstallment] {
        sortedSet(installments) {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    var paymentValues: [InstallmentValue] {
        installmentList.map { $0.paymentValue }
    }

    var status: ExpenseStatus {
        PaymentMath.expenseStatus(installments: paymentValues, isSettled: isSettled, unscheduled: unscheduledAmount)
    }

    /// Montant (dans la devise de la dépense) non couvert par l'échéancier.
    var unscheduledAmount: Double {
        PaymentMath.unscheduledAmount(total: amount, installments: paymentValues)
    }

    var paidEUR: Double {
        PaymentMath.paidEUR(totalEUR: amountEUR, rate: currencyCode == "EUR" ? 1 : rateUsed,
                            installments: paymentValues, isSettled: isSettled)
    }

    /// Reste à payer : versements non payés + solde non encore découpé en versements.
    var remainingEUR: Double {
        let rate = currencyCode == "EUR" ? 1 : rateUsed
        let scheduled = PaymentMath.remainingEUR(totalEUR: amountEUR, rate: rate, installments: paymentValues, isSettled: isSettled)
        return Money.round2(scheduled + unscheduledAmount * rate)
    }

    var nextDueInstallment: PaymentInstallment? {
        installmentList.filter { !$0.isPaid }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.first
    }
}

// MARK: - PaymentInstallment

extension PaymentInstallment {
    var kind: InstallmentKind { InstallmentKind(rawValue: kindRaw) ?? .installment }
    var isPaid: Bool { statusRaw == 1 }
    var currencyCode: String { expense?.currencyCode ?? "EUR" }

    var computedStatus: InstallmentStatus {
        PaymentMath.status(isPaid: isPaid, dueDate: dueDate)
    }

    var paymentValue: InstallmentValue {
        InstallmentValue(amount: amount, isPaid: isPaid, paidAmountEUR: paidAmountEUR, dueDate: dueDate)
    }

    /// Montant estimé en EUR (taux de paiement si payé, sinon taux de saisie de la dépense).
    var estimatedEUR: Double {
        if isPaid { return paidAmountEUR }
        let rate = currencyCode == "EUR" ? 1 : (expense?.rateUsed ?? 1)
        return Money.round2(amount * rate)
    }

    /// Marque payé : conversion au taux du jour pour un versement en devise.
    func markPaid(rateEURPerUnit: Double, payer: Traveler? = nil, date: Date = Date()) {
        statusRaw = 1
        paidDate = date
        let rate = currencyCode == "EUR" ? 1 : rateEURPerUnit
        paidRate = rate
        paidAmountEUR = Money.round2(amount * rate)
        if let payer { self.payer = payer }
    }

    func markUnpaid() {
        statusRaw = 0
        paidDate = nil
        paidRate = 0
        paidAmountEUR = 0
    }
}

// MARK: - Checklists

extension Checklist {
    var wTitle: String { (title?.isEmpty == false ? title : nil) ?? "Liste" }
    var itemList: [ChecklistItem] { sortedSet(items) { $0.sortIndex < $1.sortIndex } }
    var doneCount: Int { itemList.filter(\.isDone).count }
}

// MARK: - Activities

extension PlanActivity {
    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .other }
    var dayKey: String? { day.map { DayKey.key($0) } }
    var wTitle: String { (title?.isEmpty == false ? title : nil) ?? kind.label }
}

// MARK: - Reservations & vols

extension Reservation {
    var kind: ReservationKind { ReservationKind(rawValue: kindRaw) ?? .other }
    var wTitle: String { (title?.isEmpty == false ? title : nil) ?? kind.label }
    var segmentList: [FlightSegment] { sortedSet(flightSegments) { $0.sortIndex < $1.sortIndex } }
    var attachmentList: [Attachment] { sortedSet(attachments) { $0.sortIndex < $1.sortIndex } }
    var currencyCode: String { currency ?? "EUR" }
}

extension FlightSegment {
    var departureZone: TimeZone { TimeZone(identifier: departureTZ ?? "") ?? Airports.timeZone(for: departureIATA) ?? .current }
    var arrivalZone: TimeZone { TimeZone(identifier: arrivalTZ ?? "") ?? Airports.timeZone(for: arrivalIATA) ?? .current }
    var departureDayKey: String? { departureDate.map { DayKey.key($0, timeZone: departureZone) } }
    var durationText: String? {
        guard let departureDate, let arrivalDate else { return nil }
        return FlightTime.durationText(FlightTime.duration(departure: departureDate, arrival: arrivalDate))
    }
    var routeText: String { "\(departureIATA ?? "???") → \(arrivalIATA ?? "???")" }
    var displayAirline: String {
        if let airlineName, !airlineName.isEmpty { return airlineName }
        return Airlines.name(for: airlineCode) ?? (airlineCode ?? "")
    }
    var statusURL: URL? {
        let number = (flightNumber ?? "").replacingOccurrences(of: " ", with: "")
        guard !number.isEmpty else { return nil }
        return URL(string: "https://www.flightradar24.com/data/flights/\(number.lowercased())")
    }
}

// MARK: - Parcs

extension Park {
    var wName: String { name ?? "Parc" }
    var attractionList: [Attraction] { sortedSet(attractions) { $0.sortIndex < $1.sortIndex } }
    var mustDoProgress: (done: Int, total: Int) {
        let must = attractionList.filter { $0.priorityValue == .mustDo }
        return (must.filter { $0.doneDate != nil }.count, must.count)
    }
}

extension Attraction {
    var priorityValue: AttractionPriority { AttractionPriority(rawValue: priority) ?? .ifPossible }
    var wName: String { name ?? "Attraction" }
}

extension Traveler {
    var wName: String { (name?.isEmpty == false ? name : nil) ?? "Voyageur" }
}
