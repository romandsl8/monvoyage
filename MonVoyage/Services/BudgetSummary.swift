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

    /// Budget « sur place » : catégories non marquées « avant départ » si elles ont un budget,
    /// sinon budget total − frais avant/après départ − dépenses des catégories avant départ.
    static func onSiteBudget(trip: Trip) -> Double {
        let onSiteCats = trip.categoryList.filter { !$0.isPreDeparture }
        let planned = onSiteCats.reduce(0) { $0 + $1.plannedEUR }
        if planned > 0 { return planned }
        let preSpent = trip.expenseList.filter { $0.category?.isPreDeparture == true }.reduce(0) { $0 + $1.amountEUR }
        return max(0, trip.totalBudgetEUR - trip.preDepartureFeesEUR - trip.postDepartureFeesEUR - preSpent)
    }

    static func isOnSite(_ expense: Expense) -> Bool {
        expense.category?.isPreDeparture != true
    }

    static func daily(trip: Trip, now: Date = Date()) -> DailyBudgetResult? {
        guard let start = trip.startDate, let end = trip.endDate, !trip.isFinished(now: now) else { return nil }
        let todayKey = DayKey.key(now)
        let startKey = DayKey.key(start), endKey = DayKey.key(end)
        let daysRemaining: Int
        if trip.isOngoing(now: now) {
            daysRemaining = DayMath.daysBetween(now, end) + 1
        } else {
            daysRemaining = DayMath.daysBetween(start, end) + 1
        }
        var before = 0.0, today = 0.0
        for expense in trip.expenseList where isOnSite(expense) {
            guard let date = expense.date else { continue }
            let key = DayKey.key(date)
            guard key >= startKey && key <= endKey else { continue }
            if key < todayKey { before += expense.amountEUR }
            else if key == todayKey { today += expense.amountEUR }
        }
        return DailyBudgetCalculator.compute(onSiteBudgetEUR: onSiteBudget(trip: trip), spentBeforeTodayEUR: before,
                                             spentTodayEUR: today, daysRemaining: daysRemaining)
    }
}
