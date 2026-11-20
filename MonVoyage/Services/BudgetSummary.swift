import Foundation

/// Totaux du budget d'un voyage, en EUR.
struct BudgetSummary {
    struct CategoryLine: Identifiable {
        var id: String
        var name: String
        var symbol: String
        var plannedBudgetEUR: Double
        var spentEUR: Double
    }

    var budgetEUR: Double
    /// Somme des dépenses (prévues ou payées)
    var plannedEUR: Double
    /// Payé (acomptes et versements inclus)
    var paidEUR: Double
    var remainingEUR: Double
    /// Budget − dépenses prévues (positif = marge)
    var gapEUR: Double
    var nextDue: PaymentInstallment?
    var categories: [CategoryLine]

    init(trip: Trip) {
        let expenses = trip.expenseList
        budgetEUR = trip.totalBudgetEUR
        plannedEUR = Money.round2(expenses.reduce(0) { $0 + $1.amountEUR })
        paidEUR = Money.round2(expenses.reduce(0) { $0 + $1.paidEUR })
        remainingEUR = Money.round2(expenses.reduce(0) { $0 + $1.remainingEUR })
        gapEUR = Money.round2(budgetEUR - plannedEUR)
        preTripEUR = Money.round2(expenses.filter(\.isPreTrip).reduce(0) { $0 + $1.amountEUR })
        duringTripEUR = Money.round2(plannedEUR - preTripEUR)
        nextDue = expenses.flatMap { $0.installmentList }
            .filter { !$0.isPaid }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first
        var lines: [CategoryLine] = trip.categoryList.map { cat in
            let spent = (cat.expenses?.allObjects as? [Expense] ?? []).reduce(0) { $0 + $1.amountEUR }
            return CategoryLine(id: cat.objectID.uriRepresentation().absoluteString, name: cat.name ?? "Catégorie",
                                symbol: cat.symbol ?? "tag.fill", plannedBudgetEUR: cat.plannedEUR, spentEUR: Money.round2(spent))
        }
        let uncategorized = expenses.filter { $0.category == nil }.reduce(0) { $0 + $1.amountEUR }
        if uncategorized > 0 {
            lines.append(CategoryLine(id: "none", name: "Sans catégorie", symbol: "questionmark.circle", plannedBudgetEUR: 0, spentEUR: Money.round2(uncategorized)))
        }
        categories = lines
    }

    /// Fraction consommée du budget (0…1+), pour la jauge de la liste des voyages.
    var consumedFraction: Double {
        guard budgetEUR > 0 else { return 0 }
        return plannedEUR / budgetEUR
    }

    // MARK: - Budget restant par jour

    /// Dépenses réglées avant le voyage (vols, hôtel, billets…).
    var preTripEUR: Double = 0
    /// Dépenses sur place (pendant le voyage).
    var duringTripEUR: Double = 0

    /// Budget « sur place » :
    /// - si un budget total est défini : budget total − frais avant/après − dépenses « avant le voyage » ;
    /// - sinon : somme des budgets des catégories non marquées « avant départ ».
    static func onSiteBudget(trip: Trip) -> Double {
        if trip.totalBudgetEUR > 0 {
            let preTrip = trip.expenseList.filter(\.isPreTrip).reduce(0) { $0 + $1.amountEUR }
            return max(0, trip.totalBudgetEUR - trip.preDepartureFeesEUR - trip.postDepartureFeesEUR - preTrip)
        }
        return trip.categoryList.filter { !$0.isPreDeparture }.reduce(0) { $0 + $1.plannedEUR }
    }

    static func isOnSite(_ expense: Expense) -> Bool {
        !expense.isPreTrip
    }

    /// Budget restant par jour. Avant le départ : budget sur place ÷ nombre de jours du voyage
    /// (`isBeforeTrip` = true, rien n'est « dépensé aujourd'hui »).
    static func daily(trip: Trip, now: Date = Date()) -> DailyBudgetResult? {
        guard let start = trip.startDate, let end = trip.endDate, !trip.isFinished(now: now) else { return nil }
        let todayKey = DayKey.key(now)
        let endKey = DayKey.key(end)
        let ongoing = trip.isOngoing(now: now)
        let daysRemaining = ongoing ? DayMath.daysBetween(now, end) + 1 : DayMath.daysBetween(start, end) + 1
        var before = 0.0, today = 0.0
        for expense in trip.expenseList where isOnSite(expense) {
            guard let date = expense.date else { continue }
            let key = DayKey.key(date)
            guard key <= endKey else { continue }
            if ongoing && key == todayKey { today += expense.amountEUR } else if key <= todayKey || !ongoing { before += expense.amountEUR }
        }
        var result = DailyBudgetCalculator.compute(onSiteBudgetEUR: onSiteBudget(trip: trip), spentBeforeTodayEUR: before,
                                                   spentTodayEUR: today, daysRemaining: daysRemaining)
        if !ongoing {
            result.isBeforeTrip = true
            result.status = result.perDayEUR > 0 ? 0 : 2
        }
        return result
    }
}
