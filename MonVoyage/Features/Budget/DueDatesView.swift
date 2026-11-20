import SwiftUI
import CoreData

/// Vue Échéances : versements à venir triés par date, retards en rouge, total par mois.
struct DueDatesView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var nav: TripNavigation
    @State private var showPaid = false
    @State private var paidTick = 0

    private var installments: [PaymentInstallment] {
        trip.expenseList.flatMap { $0.installmentList }
            .filter { showPaid || !$0.isPaid }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var months: [(key: String, title: String, items: [PaymentInstallment])] {
        let cal = DayKey.calendar()
        var groups: [String: [PaymentInstallment]] = [:]
        var titles: [String: String] = [:]
        for inst in installments {
            let date = inst.dueDate ?? Date()
            let c = cal.dateComponents([.year, .month], from: date)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            groups[key, default: []].append(inst)
            titles[key] = date.formatted(.dateTime.month(.wide).year().locale(SharedLocale.fr)).capitalized
        }
        return groups.keys.sorted().map { key in
            (key: key, title: titles[key] ?? key, items: groups[key] ?? [])
        }
    }

    var body: some View {
        List {
            if installments.isEmpty {
                EmptyState(symbol: "calendar.badge.checkmark", title: "Aucune échéance",
                           message: "Ajoutez un paiement en plusieurs fois sur une dépense pour suivre acomptes et versements.")
                    .listRowBackground(Color.clear)
            }
            ForEach(months, id: \.key) { month in
                Section {
                    ForEach(month.items, id: \.objectID) { inst in
                        row(inst)
                            .swipeActions(edge: .leading) {
                                if inst.isPaid {
                                    Button { inst.markUnpaid(); context.saveIfNeeded() } label: { Label("Non payé", systemImage: "arrow.uturn.backward") }
                                } else {
                                    Button {
                                        inst.markPaid(rateEURPerUnit: rates.rate(for: inst.currencyCode))
                                        context.saveIfNeeded()
                                        paidTick += 1
                                    } label: { Label("Payé", systemImage: "checkmark") }
                                    .tint(.green)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { if let e = inst.expense { nav.present(.editExpense(e.objectID)) } }
                    }
                } header: {
                    HStack {
                        Text(month.title)
                        Spacer()
                        Text(Fmt.eur(month.items.reduce(0) { $0 + $1.estimatedEUR })).monospacedDigit()
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

    private func row(_ inst: PaymentInstallment) -> some View {
        let status = inst.computedStatus
        return HStack {
            Image(systemName: status == .paid ? "checkmark.circle.fill" : (status == .overdue ? "exclamationmark.circle.fill" : "circle"))
                .foregroundStyle(status == .paid ? .green : (status == .overdue ? Color.red : Color.secondary))
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(inst.expense?.wTitle ?? "Dépense").font(.body)
                Text("\(inst.kind.label) · \(inst.dueDate.map { Fmt.day($0) } ?? "sans date")\(inst.payer.map { " · \($0.wName)" } ?? "")")
                    .font(.caption).foregroundStyle(status == .overdue ? Color.red : Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Fmt.money(inst.amount, inst.currencyCode)).monospacedDigit().fontWeight(.semibold)
                    .foregroundStyle(status == .overdue ? Color.red : Color.primary)
                if inst.currencyCode != "EUR" { Text(Fmt.eur(inst.estimatedEUR)).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.label)
    }
}
