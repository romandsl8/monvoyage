import Foundation

enum InstallmentStatus: Equatable {
    case upcoming, paid, overdue
    var label: String {
        switch self {
        case .upcoming: return "À venir"
        case .paid: return "Payé"
        case .overdue: return "En retard"
        }
    }
}

enum ExpenseStatus: Equatable {
    case planned, partial, settled
    var label: String {
        switch self {
        case .planned: return "Prévu"
        case .partial: return "Partiellement payé"
        case .settled: return "Soldé"
        }
    }
    var symbol: String {
        switch self {
        case .planned: return "clock"
        case .partial: return "circle.lefthalf.filled"
        case .settled: return "checkmark.circle.fill"
        }
    }
}

/// Valeur « pure » d'un versement (pour les calculs testables).
struct InstallmentValue: Equatable {
    var amount: Double
    var isPaid: Bool
    var paidAmountEUR: Double
    var dueDate: Date?
}

/// Un versement à créer (sortie du planificateur).
struct PlannedInstallment: Equatable {
    var kind: InstallmentKind
    var amount: Double
    var dueDate: Date
}

enum PaymentMath {
    static func status(isPaid: Bool, dueDate: Date?, now: Date = Date()) -> InstallmentStatus {
        if isPaid { return .paid }
        guard let dueDate else { return .upcoming }
        return DayKey.key(dueDate) < DayKey.key(now) ? .overdue : .upcoming
    }

    static func expenseStatus(installments: [InstallmentValue], isSettled: Bool) -> ExpenseStatus {
        if installments.isEmpty { return isSettled ? .settled : .planned }
        let paid = installments.filter(\.isPaid).count
        if paid == 0 { return .planned }
        if paid == installments.count { return .settled }
        return .partial
    }

    static func paidEUR(totalEUR: Double, rate: Double, installments: [InstallmentValue], isSettled: Bool) -> Double {
        if installments.isEmpty { return isSettled ? totalEUR : 0 }
        return Money.round2(installments.filter(\.isPaid).reduce(0) { $0 + $1.paidAmountEUR })
    }

    static func remainingEUR(totalEUR: Double, rate: Double, installments: [InstallmentValue], isSettled: Bool) -> Double {
        if installments.isEmpty { return isSettled ? 0 : totalEUR }
        return Money.round2(installments.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount * rate })
    }

    /// Écart entre la somme des versements et le total (0 = cohérent).
    static func scheduleGap(total: Double, installments: [Double]) -> Double {
        Money.round2(total - installments.reduce(0, +))
    }

    /// Répartit `remaining` en `count` versements égaux, reliquat d'arrondi sur le dernier.
    static func splitEqually(_ remaining: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let cents = Int((remaining * 100).rounded(.toNearestOrAwayFromZero))
        let base = cents / count
        var parts = Array(repeating: base, count: count)
        parts[count - 1] += cents - base * count
        return parts.map { Double($0) / 100 }
    }

    /// Construit un échéancier : acompte (montant ou %) puis solde en N fois, un versement par mois.
    static func plan(total: Double, deposit: Double?, depositIsPercent: Bool, depositDate: Date,
                     count: Int, firstInstallmentDate: Date, monthsBetween: Int = 1) -> [PlannedInstallment] {
        var result: [PlannedInstallment] = []
        var depositAmount = 0.0
        if let deposit, deposit > 0 {
            depositAmount = Money.round2(depositIsPercent ? total * deposit / 100 : deposit)
            depositAmount = min(depositAmount, total)
            result.append(PlannedInstallment(kind: .deposit, amount: depositAmount, dueDate: depositDate))
        }
        let remaining = Money.round2(total - depositAmount)
        guard remaining > 0, count > 0 else { return result }
        let cal = DayKey.calendar()
        for (i, part) in splitEqually(remaining, count: count).enumerated() {
            let date = cal.date(byAdding: .month, value: i * max(1, monthsBetween), to: firstInstallmentDate) ?? firstInstallmentDate
            result.append(PlannedInstallment(kind: .installment, amount: part, dueDate: date))
        }
        return result
    }
}

/// Budget restant par jour pendant le voyage.
struct DailyBudgetResult: Equatable {
    var perDayEUR: Double
    var remainingEUR: Double
    var daysRemaining: Int
    var spentTodayEUR: Double
    /// 0 = vert, 1 = orange, 2 = rouge
    var status: Int
}

enum DailyBudgetCalculator {
    /// (budget sur place − dépensé avant aujourd'hui) ÷ jours restants (aujourd'hui inclus).
    /// Couleur : vert ≤ 80 % du montant du jour, orange ≤ 100 %, rouge au-delà.
    static func compute(onSiteBudgetEUR: Double, spentBeforeTodayEUR: Double, spentTodayEUR: Double,
                        daysRemaining: Int) -> DailyBudgetResult {
        let days = max(1, daysRemaining)
        let remaining = onSiteBudgetEUR - spentBeforeTodayEUR
        let perDay = Money.round2(remaining / Double(days))
        let status: Int
        if perDay <= 0 { status = 2 }
        else if spentTodayEUR <= perDay * 0.8 { status = 0 }
        else if spentTodayEUR <= perDay { status = 1 }
        else { status = 2 }
        return DailyBudgetResult(perDayEUR: perDay, remainingEUR: Money.round2(remaining - spentTodayEUR),
                                 daysRemaining: days, spentTodayEUR: spentTodayEUR, status: status)
    }
}
