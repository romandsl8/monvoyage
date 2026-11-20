import SwiftUI
import CoreData

/// Vue « Aujourd'hui » : tout ce qui compte pendant le voyage, sur un seul écran.
/// Avant le départ : compte à rebours et préparation.
struct TodayView: View {
    @ObservedObject var trip: Trip
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var nav: TripNavigation
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var affluence: AffluenceService
    @EnvironmentObject private var queueTimes: QueueTimesService

    private var todayKey: String { DayKey.key(Date()) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(spacing: 16) {
                    header(now: timeline.date)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        cards(now: timeline.date)
                    }
                }
                .padding()
                .padding(.bottom, 80)   // place pour le bouton « + » flottant
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .groupedBackground()
        .navigationTitle(trip.wName)
        .refreshable { await refresh(force: true) }
        .task { await refresh(force: false) }
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton(label: "Ajouter une dépense") {
                nav.present(.newExpense(ExpensePrefill(currency: trip.isOngoing() ? trip.currencyCode : "EUR")))
            }
        }
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)] : [GridItem(.flexible())]
    }

    // MARK: En-tête

    @ViewBuilder
    private func header(now: Date) -> some View {
        VStack(spacing: 12) {
            HeroCard(tint: trip.accent) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let city = trip.city, !city.isEmpty {
                            Label(city, systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.semibold))
                                .opacity(0.9)
                        }
                        if trip.isOngoing(now: now) {
                            Text(Fmt.longDay(now, timeZone: trip.tripTimeZone).capitalized)
                                .font(.title.bold()).fontDesign(.rounded)
                        } else if let start = trip.startDate {
                            // Avant (ou après) le voyage : les dates du voyage, pas celle du jour.
                            Text(Fmt.longDay(start).capitalized)
                                .font(.title.bold()).fontDesign(.rounded)
                                .minimumScaleFactor(0.7).lineLimit(1)
                            if let end = trip.endDate, DayKey.key(end) != DayKey.key(start) {
                                Text("au \(Fmt.longDay(end)) · \(trip.dayKeys.count) jours")
                                    .font(.subheadline).opacity(0.9)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if !trip.isOngoing(now: now), let days = trip.daysUntilDeparture(now: now), days >= 0 {
                        VStack(spacing: 0) {
                            Text("J-\(days)").font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text("avant le départ").font(.caption.weight(.semibold)).opacity(0.9)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.18), in: .rect(cornerRadius: 18, style: .continuous))
                        .accessibilityElement(children: .combine)
                    } else if trip.isOngoing(now: now), let index = trip.dayKeys.firstIndex(of: DayKey.key(now)) {
                        VStack(spacing: 0) {
                            Text("Jour \(index + 1)").font(.title2.weight(.heavy)).fontDesign(.rounded)
                            Text("sur \(trip.dayKeys.count)").font(.caption.weight(.semibold)).opacity(0.9)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.18), in: .rect(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            let alerts = DocumentAlerts.allAlerts(trip: trip)
            if !alerts.isEmpty && !trip.isFinished(now: now) {
                Card {
                    CardTitle(title: "À vérifier", symbol: "exclamationmark.triangle.fill", tint: .orange)
                    ForEach(alerts, id: \.self) { alert in
                        Text(alert).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button { nav.open(.tripSettings) } label: { Label("Passeports et ESTA", systemImage: "person.text.rectangle") }
                        .buttonStyle(.glass).font(.caption)
                }
            }
        }
    }

    // MARK: Cartes

    @ViewBuilder
    private func cards(now: Date) -> some View {
        nextActivitiesCard(now: now)
        weatherCard(now: now)
        if !trip.parks(on: DayKey.key(now)).isEmpty { parksCard(now: now) }
        dailyBudgetCard(now: now)
        todayExpensesCard(now: now)
        upcomingCard(now: now)
    }

    private func nextActivitiesCard(now: Date) -> some View {
        let upcoming = trip.activityList.filter { ($0.time ?? .distantPast) > now }.prefix(2)
        let nextFlight = trip.flightSegments.first { ($0.departureDate ?? .distantPast) > now }
        return Card {
            CardTitle(title: "À suivre", symbol: "clock.fill", tint: trip.accent)
            if let flight = nextFlight, let dep = flight.departureDate, dep.timeIntervalSince(now) < 2 * 86400 {
                FlightLine(segment: flight)
                Text("Décollage dans ") + Text(dep, style: .relative)
            }
            if upcoming.isEmpty && nextFlight == nil {
                Text("Rien de prévu. Ajoutez des activités dans le planning.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(upcoming), id: \.objectID) { activity in
                VStack(alignment: .leading, spacing: 2) {
                    ActivityLine(activity: activity, timeZone: trip.tripTimeZone)
                    if let day = activity.day, activity.dayKey != DayKey.key(now) {
                        Text(Fmt.day(day)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 58)
                    }
                }
                .onTapGesture { nav.present(.editActivity(activity.objectID)) }
            }
        }
    }

    private func weatherCard(now: Date) -> some View {
        let key = trip.dayKeys.contains(DayKey.key(now)) ? DayKey.key(now) : (trip.dayKeys.first ?? DayKey.key(now))
        return Card {
            CardTitle(title: key == DayKey.key(now) ? "Météo du jour" : "Météo du premier jour", symbol: "cloud.sun.fill", tint: trip.accent)
            if let id = trip.id?.uuidString, let w = weather.weather(tripKey: id, dayKey: key) {
                WeatherBadge(weather: w, updatedAt: weather.updatedAt(tripKey: id))
            } else {
                Text("Météo indisponible (hors ligne ou destination non renseignée).").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func parksCard(now: Date) -> some View {
        let key = DayKey.key(now)
        let parks = trip.parks(on: key)
        return Card {
            CardTitle(title: "Parcs du jour", symbol: "sparkles", tint: trip.accent)
            ForEach(parks, id: \.objectID) { park in
                CrowdBadge(park: park, info: affluence.info(park: park, dayKey: key))
                let remaining = park.attractionList.filter { $0.doneDate == nil && $0.assignedDay.map { DayKey.key($0) } == key }
                let waits = queueTimes.waitTimes[park.queueTimesID] ?? queueTimes.cachedWaits(parkID: park.queueTimesID)
                ForEach(remaining.prefix(6), id: \.objectID) { a in
                    HStack {
                        Circle().fill(a.priorityValue.color).frame(width: 8, height: 8)
                        Text(a.wName).font(.subheadline)
                        Spacer()
                        if let wait = waits?.rides[a.queueTimesID], waits?.open[a.queueTimesID] != false {
                            Text("\(wait) min").font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }
                }
                if remaining.count > 6 { Text("+ \(remaining.count - 6) autres").font(.caption).foregroundStyle(.secondary) }
            }
            QueueTimesCredit()
        }
    }

    private func dailyBudgetCard(now: Date) -> some View {
        Card {
            CardTitle(title: "Budget restant par jour", symbol: "gauge.with.dots.needle.50percent", tint: trip.accent)
            if BudgetSummary.onSiteBudget(trip: trip) <= 0 {
                Text("Définissez le budget total du voyage, ou un budget par catégorie de dépenses sur place (Repas, Transport…), pour connaître ce qu'il reste à dépenser chaque jour.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button("Budget total") { nav.present(.editTrip) }
                    Button("Catégories") { nav.open(.budget) }
                }
                .buttonStyle(.glass)
                .font(.caption)
            } else if let daily = BudgetSummary.daily(trip: trip, now: now), daily.isBeforeTrip {
                HStack(alignment: .firstTextBaseline) {
                    BigNumber(label: "Par jour sur place", value: Fmt.eurShort(daily.perDayEUR), tint: trip.accent)
                    Spacer()
                    BigNumber(label: "En dollars", value: Fmt.usd(Money.fromEUR(daily.perDayEUR, currency: "USD", rateEURPerUnit: rates.usdToEUR)))
                }
                Text("Prévision pour les \(daily.daysRemaining) jours du voyage, après déduction des dépenses réglées avant le départ (\(Fmt.eurShort(BudgetSummary(trip: trip).preTripEUR))). Le suivi jour par jour commencera le premier jour du voyage.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let daily = BudgetSummary.daily(trip: trip, now: now) {
                HStack(alignment: .firstTextBaseline) {
                    BigNumber(label: "Aujourd'hui", value: Fmt.eurShort(daily.perDayEUR), tint: StatusColor.budget(daily.status))
                    Spacer()
                    BigNumber(label: "En dollars", value: Fmt.usd(Money.fromEUR(daily.perDayEUR, currency: "USD", rateEURPerUnit: rates.usdToEUR)))
                }
                ProgressBar(fraction: daily.perDayEUR > 0 ? daily.spentTodayEUR / daily.perDayEUR : 1, tint: StatusColor.budget(daily.status))
                Text("Dépensé aujourd'hui : \(Fmt.eur(daily.spentTodayEUR)) · \(daily.daysRemaining) jour\(daily.daysRemaining > 1 ? "s" : "") restant\(daily.daysRemaining > 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Le voyage est terminé.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func todayExpensesCard(now: Date) -> some View {
        let expenses = trip.expenses(on: DayKey.key(now))
        return Card {
            HStack {
                CardTitle(title: "Dépenses du jour", symbol: "creditcard.fill", tint: trip.accent)
                Spacer()
                Button { nav.present(.scanReceipt) } label: { Label("Scanner", systemImage: "doc.viewfinder") }
                    .buttonStyle(.glass).font(.caption)
            }
            if expenses.isEmpty {
                Text("Aucune dépense aujourd'hui.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(expenses, id: \.objectID) { e in
                    ExpenseRow(expense: e).onTapGesture { nav.present(.editExpense(e.objectID)) }
                }
                Text("Total : \(Fmt.eur(expenses.reduce(0) { $0 + $1.amountEUR }))").font(.subheadline.weight(.semibold))
            }
        }
    }

    private func upcomingCard(now: Date) -> some View {
        let installments = DueItem.all(for: trip, includePaid: false).prefix(3)
        let reminders = trip.reminderList.filter { ($0.date ?? .distantPast) > now }.prefix(3)
        return Card {
            CardTitle(title: "Échéances et rappels", symbol: "bell.fill", tint: trip.accent)
            if installments.isEmpty && reminders.isEmpty {
                Text("Rien à venir.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(installments)) { item in
                HStack {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(item.status == .overdue ? Color.red : trip.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.expense.wTitle).lineLimit(1)
                        Text(item.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Fmt.money(item.amount, item.currency)) · \(item.date.map { Fmt.day($0) } ?? "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                .onTapGesture { nav.open(.dueDates) }
            }
            ForEach(Array(reminders), id: \.objectID) { r in
                HStack {
                    Image(systemName: "bell").foregroundStyle(trip.accent)
                    Text(r.title ?? "Rappel")
                    Spacer()
                    if let d = r.date { Text(Fmt.dateTime(d)).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func refresh(force: Bool) async {
        if let id = trip.id?.uuidString {
            await weather.refresh(tripKey: id, latitude: trip.latitude, longitude: trip.longitude, dayKeys: trip.dayKeys, force: force)
        }
        await affluence.refresh(force: force)
        for park in trip.parks(on: todayKey) where park.queueTimesID > 0 {
            await queueTimes.refreshWaits(parkID: park.queueTimesID)
        }
    }
}
