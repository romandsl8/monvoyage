import SwiftUI
import CoreData

/// Une ligne de la vue Échéances : un versement, un solde non découpé en versements,
/// ou une dépense pas encore payée (sans échéancier).
struct DueItem: Identifiable {
    enum Kind {
        case installment(PaymentInstallment)
        case unscheduled(Expense)
        case unpaid(Expense)
    }

    let id: String
    let kind: Kind
    let expense: Expense
    let date: Date?
    let amount: Double
    let currency: String
    let amountEUR: Double
    let label: String
    let isPaid: Bool

    var status: InstallmentStatus { PaymentMath.status(isPaid: isPaid, dueDate: date) }

    /// Toutes les sommes dues d'un voyage (les payées seulement si `includePaid`).
    static func all(for trip: Trip, includePaid: Bool) -> [DueItem] {
        var items: [DueItem] = []
        for expense in trip.expenseList {
            let rate = expense.currencyCode == "EUR" ? 1 : expense.rateUsed
            let uri = expense.objectID.uriRepresentation().absoluteString
            let installments = expense.installmentList
            if installments.isEmpty {
                guard !expense.isSettled || includePaid else { continue }
                items.append(DueItem(id: "unpaid-\(uri)", kind: .unpaid(expense), expense: expense, date: expense.date,
                                     amount: expense.amount, currency: expense.currencyCode, amountEUR: expense.amountEUR,
                                     label: expense.isSettled ? "Payé" : "À payer", isPaid: expense.isSettled))
                continue
            }
            for inst in installments where includePaid || !inst.isPaid {
                items.append(DueItem(id: inst.objectID.uriRepresentation().absoluteString, kind: .installment(inst),
                                     expense: expense, date: inst.dueDate, amount: inst.amount, currency: inst.currencyCode,
                                     amountEUR: inst.estimatedEUR, label: inst.kind.label, isPaid: inst.isPaid))
            }
            let gap = expense.unscheduledAmount
            if gap >= 0.01 {
                let lastDue = installments.compactMap(\.dueDate).max()
                items.append(DueItem(id: "gap-\(uri)", kind: .unscheduled(expense), expense: expense,
                                     date: lastDue ?? expense.date, amount: gap, currency: expense.currencyCode,
                                     amountEUR: Money.round2(gap * rate), label: "Solde restant", isPaid: false))
            }
        }
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

/// Vue Échéances : sommes à payer triées par date, retards en rouge, total par mois.
struct DueDatesView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var nav: TripNavigation
    @State private var showPaid = false
    @State private var paidTick = 0

    private var items: [DueItem] { DueItem.all(for: trip, includePaid: showPaid) }

    private var months: [(key: String, title: String, items: [DueItem])] {
        let cal = DayKey.calendar()
        var groups: [String: [DueItem]] = [:]
        var titles: [String: String] = [:]
        for item in items {
            guard let date = item.date else {
                groups["9999-99", default: []].append(item)
                titles["9999-99"] = "Sans date"
                continue
            }
            let c = cal.dateComponents([.year, .month], from: date)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            groups[key, default: []].append(item)
            titles[key] = date.formatted(.dateTime.month(.wide).year().locale(SharedLocale.fr)).capitalized
        }
        return groups.keys.sorted().map { key in
            (key: key, title: titles[key] ?? key, items: groups[key] ?? [])
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                EmptyState(symbol: "calendar.badge.checkmark", title: "Rien à payer",
                           message: "Les acomptes, versements et dépenses pas encore réglées apparaîtront ici.")
                    .listRowBackground(Color.clear)
            }
            ForEach(months, id: \.key) { month in
                Section {
                    ForEach(month.items) { item in
                        row(item)
                            .swipeActions(edge: .leading) { swipeAction(item) }
                            .contentShape(.rect)
                            .onTapGesture { nav.present(.editExpense(item.expense.objectID)) }
                    }
                } header: {
                    HStack {
                        Text(month.title)
                        Spacer()
                        Text(Fmt.eur(month.items.filter { !$0.isPaid }.reduce(0) { $0 + $1.amountEUR })).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Échéances")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showPaid) { Label("Afficher les payés", systemImage: "checkmark.circle") }
                    .toggleStyle(.button)
            }
        }
        .sensoryFeedback(.success, trigger: paidTick)
    }

    @ViewBuilder
    private func swipeAction(_ item: DueItem) -> some View {
        switch item.kind {
        case .installment(let inst):
            if inst.isPaid {
                Button { inst.markUnpaid(); context.saveIfNeeded() } label: { Label("Non payé", systemImage: "arrow.uturn.backward") }
            } else {
                Button { markPaid { inst.markPaid(rateEURPerUnit: rates.rate(for: inst.currencyCode)) } } label: {
                    Label("Payé", systemImage: "checkmark")
                }
                .tint(.green)
            }
        case .unpaid(let expense):
            Button { markPaid { expense.isSettled.toggle() } } label: {
                Label(expense.isSettled ? "Non payé" : "Payé", systemImage: expense.isSettled ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(expense.isSettled ? .gray : .green)
        case .unscheduled(let expense):
            // Le solde est réglé en une fois : on l'ajoute comme versement payé.
            Button {
                markPaid {
                    let inst = context.make(PaymentInstallment.self, trip: trip)
                    inst.kindRaw = InstallmentKind.installment.rawValue
                    inst.amount = expense.unscheduledAmount
                    inst.dueDate = Date()
                    inst.sortIndex = Int32(expense.installmentList.count)
                    inst.payer = expense.paidBy
                    inst.expense = expense
                    inst.markPaid(rateEURPerUnit: rates.rate(for: expense.currencyCode))
                }
            } label: {
                Label("Soldé", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    private func markPaid(_ change: () -> Void) {
        change()
        context.saveIfNeeded()
        paidTick += 1
    }

    private func row(_ item: DueItem) -> some View {
        let status = item.status
        let detail = [item.label, item.date.map { Fmt.day($0) } ?? "sans date", item.expense.paidBy?.wName]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack {
            Image(systemName: status == .paid ? "checkmark.circle.fill" : (status == .overdue ? "exclamationmark.circle.fill" : "circle"))
                .foregroundStyle(status == .paid ? Color.green : (status == .overdue ? Color.red : Color.secondary))
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.expense.wTitle).font(.body).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(status == .overdue ? Color.red : Color.secondary).lineLimit(1)
                if case .unscheduled = item.kind {
                    Text("Non découpé en versements : touchez pour planifier, ou balayez pour le marquer soldé.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Fmt.money(item.amount, item.currency)).monospacedDigit().fontWeight(.semibold)
                    .foregroundStyle(status == .overdue ? Color.red : Color.primary)
                    .lineLimit(1).fixedSize()
                if item.currency != "EUR" { Text(Fmt.eur(item.amountEUR)).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.label)
    }
}
