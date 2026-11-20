import SwiftUI
import CoreData

/// Brouillon d'un versement.
struct InstallmentDraft: Identifiable, Equatable {
    var id = UUID()
    var objectID: NSManagedObjectID?
    var kind: InstallmentKind = .installment
    var amountText = ""
    var dueDate = Date()
    var isPaid = false
    var paidDate: Date?
    var paidRate: Double = 0
    var payerID: NSManagedObjectID?

    var amount: Double { Money.parse(amountText) ?? 0 }
}

/// Brouillon du paiement d'une dépense : catégorie, moment (avant / pendant le voyage),
/// payé ou non, échéancier. Partagé par l'éditeur de dépense et l'éditeur de réservation.
struct PaymentDraft: Equatable {
    var categoryID: NSManagedObjectID?
    var payerID: NSManagedObjectID?
    var phase: ExpensePhase = .duringTrip
    /// L'utilisateur a choisi le moment lui-même (on ne le recalcule plus).
    var phaseChosen = false
    var isSettled = true
    var useSchedule = false
    var installments: [InstallmentDraft] = []

    // Préparation de l'échéancier
    var depositText = ""
    var depositIsPercent = false
    var depositDate = Date()
    /// L'acompte est en général réglé à la réservation.
    var depositPaid = true
    var splitCount = 3
    var firstInstallmentDate = Date().addingTimeInterval(30 * 86400)

    init() {}

    /// Reprend une dépense existante.
    init(expense: Expense) {
        categoryID = expense.category?.objectID
        payerID = expense.paidBy?.objectID
        phase = expense.phase == .auto ? (expense.isPreTrip ? .beforeTrip : .duringTrip) : expense.phase
        phaseChosen = true
        isSettled = expense.isSettled
        installments = expense.installmentList.map { inst in
            InstallmentDraft(objectID: inst.objectID, kind: inst.kind, amountText: Fmt.number(inst.amount),
                             dueDate: inst.dueDate ?? Date(), isPaid: inst.isPaid, paidDate: inst.paidDate,
                             paidRate: inst.paidRate, payerID: inst.payer?.objectID)
        }
        useSchedule = !installments.isEmpty
    }

    func scheduleGap(total: Double) -> Double {
        PaymentMath.scheduleGap(total: total, installments: installments.map(\.amount))
    }

    /// « Répartir le solde en N fois égales » (les versements déjà payés sont conservés).
    /// `rate` : taux EUR pour 1 unité, utilisé si l'acompte est marqué payé.
    mutating func generateSchedule(total: Double, rate: Double = 1) {
        let paid = installments.filter(\.isPaid)
        let alreadyPaid = paid.reduce(0) { $0 + $1.amount }
        // Les versements déjà payés sont gardés : on ne replanifie que ce qui reste à payer.
        let plan = PaymentMath.plan(total: Money.round2(total - alreadyPaid),
                                    deposit: paid.isEmpty ? Money.parse(depositText) : nil,
                                    depositIsPercent: depositIsPercent, depositDate: depositDate,
                                    count: splitCount, firstInstallmentDate: firstInstallmentDate)
        let fresh = plan.map { p -> InstallmentDraft in
            var item = InstallmentDraft(kind: p.kind, amountText: Fmt.number(p.amount), dueDate: p.dueDate, payerID: payerID)
            if p.kind == .deposit && depositPaid {
                item.isPaid = true
                item.paidDate = depositDate
                item.paidRate = rate
            }
            return item
        }
        installments = paid + fresh
    }

    /// Montant d'acompte saisi (montant ou %), 0 si aucun.
    func depositAmount(total: Double) -> Double {
        guard let value = Money.parse(depositText), value > 0 else { return 0 }
        return Money.round2(depositIsPercent ? total * value / 100 : value)
    }
}

/// Sections de formulaire : catégorie, moment, paiement, échéancier.
struct PaymentSections: View {
    @Binding var draft: PaymentDraft
    let amount: Double
    let currency: String
    let date: Date
    @ObservedObject var trip: Trip
    var showCategory = true
    @EnvironmentObject private var rates: ExchangeRateService
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        Section {
            if showCategory {
                Picker("Catégorie", selection: $draft.categoryID) {
                    Text("Aucune").tag(NSManagedObjectID?.none)
                    ForEach(trip.categoryList, id: \.objectID) { cat in
                        Label(cat.name ?? "", systemImage: cat.symbol ?? "tag").tag(NSManagedObjectID?.some(cat.objectID))
                    }
                }
            }
            Picker("Moment", selection: Binding(get: { draft.phase == .auto ? .duringTrip : draft.phase },
                                                set: { draft.phase = $0; draft.phaseChosen = true })) {
                Text("Avant le voyage").tag(ExpensePhase.beforeTrip)
                Text("Pendant le voyage").tag(ExpensePhase.duringTrip)
            }
            .pickerStyle(.segmented)
            Picker("Payé par", selection: $draft.payerID) {
                Text("—").tag(NSManagedObjectID?.none)
                ForEach(trip.travelerList, id: \.objectID) { t in
                    Text(t.wName).tag(NSManagedObjectID?.some(t.objectID))
                }
            }
            Toggle("Paiement en plusieurs fois", isOn: $draft.useSchedule.animation())
            if !draft.useSchedule {
                Toggle("Déjà payé", isOn: $draft.isSettled)
            }
        } header: {
            Text("Budget et paiement")
        } footer: {
            Text(draft.phase == .beforeTrip
                 ? "Réglé avant le départ (vol, hôtel, billets…) : compté dans le budget total, pas dans le budget par jour sur place."
                 : "Dépensé sur place : compté dans le budget restant par jour.")
        }
        .onChange(of: draft.categoryID) { _, _ in suggestPhase() }
        .onChange(of: date) { _, _ in suggestPhase() }
        .onAppear { suggestPhase() }

        if draft.useSchedule {
            Section {
                AmountField(title: "Acompte", text: $draft.depositText, currency: draft.depositIsPercent ? "%" : currency)
                Toggle("Acompte en pourcentage", isOn: $draft.depositIsPercent)
                DatePicker("Date de l'acompte", selection: $draft.depositDate, displayedComponents: .date)
                Toggle("Acompte déjà payé", isOn: $draft.depositPaid)
                Stepper("Solde en \(draft.splitCount) fois", value: $draft.splitCount, in: 1...24)
                DatePicker("1er versement", selection: $draft.firstInstallmentDate, displayedComponents: .date)
                Button {
                    draft.generateSchedule(total: amount, rate: currency == "EUR" ? 1 : rates.rate(for: currency))
                } label: {
                    Label("Répartir le solde en \(draft.splitCount) fois égales", systemImage: "divide.circle")
                }
                .disabled(amount <= 0)
            } header: {
                Text("Préparer l'échéancier")
            } footer: {
                Text("Un versement par mois à partir du 1er versement. Le reliquat d'arrondi va sur le dernier.")
            }

            Section {
                ForEach($draft.installments) { $item in
                    InstallmentDraftRow(draft: $item, currency: currency, travelers: trip.travelerList, rate: rates.rate(for: currency))
                }
                .onDelete { draft.installments.remove(atOffsets: $0) }
                Button {
                    draft.installments.append(InstallmentDraft(dueDate: draft.installments.last?.dueDate.addingTimeInterval(30 * 86400) ?? Date(),
                                                               payerID: draft.payerID))
                } label: {
                    Label("Ajouter un versement", systemImage: "plus.circle")
                }
            } header: {
                Text("Versements")
            } footer: {
                let gap = draft.scheduleGap(total: amount)
                if !draft.installments.isEmpty && abs(gap) >= 0.01 {
                    Label("La somme des versements diffère du total de \(Fmt.money(abs(gap), currency)) (\(gap > 0 ? "il manque" : "en trop")).",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if !draft.installments.isEmpty {
                    Label("Échéancier cohérent avec le total.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
    }

    private func suggestPhase() {
        guard !draft.phaseChosen else { return }
        let category = draft.categoryID.flatMap { try? context.existingObject(with: $0) as? BudgetCategory }
        draft.phase = ExpensePhase.suggested(category: category, date: date, trip: trip)
    }
}

/// Écrit le brouillon de paiement dans une dépense (catégorie, moment, versements).
enum PaymentSync {
    @MainActor
    static func apply(_ source: PaymentDraft, to expense: Expense, currency: String, trip: Trip,
                      rates: ExchangeRateService, context: NSManagedObjectContext) {
        var draft = source
        // Acompte saisi sans avoir touché « Répartir » : l'échéancier est créé automatiquement.
        if draft.useSchedule && draft.installments.isEmpty && expense.amount > 0 {
            draft.generateSchedule(total: expense.amount, rate: currency == "EUR" ? 1 : rates.rate(for: currency))
        }
        expense.category = draft.categoryID.flatMap { try? context.existingObject(with: $0) as? BudgetCategory }
        expense.paidBy = draft.payerID.flatMap { try? context.existingObject(with: $0) as? Traveler }
        expense.phaseRaw = (draft.phase == .auto ? ExpensePhase.duringTrip : draft.phase).rawValue

        let keep = draft.useSchedule ? draft.installments : []
        let keptIDs = Set(keep.compactMap(\.objectID))
        for existing in expense.installmentList where !keptIDs.contains(existing.objectID) {
            context.delete(existing)
        }
        for (index, item) in keep.enumerated() {
            let inst: PaymentInstallment
            if let id = item.objectID, let existing = try? context.existingObject(with: id) as? PaymentInstallment {
                inst = existing
            } else {
                inst = context.make(PaymentInstallment.self, trip: trip)
                inst.expense = expense
            }
            inst.kindRaw = item.kind.rawValue
            inst.amount = item.amount
            inst.dueDate = item.dueDate
            inst.sortIndex = Int32(index)
            inst.payer = item.payerID.flatMap { try? context.existingObject(with: $0) as? Traveler }
            if item.isPaid {
                if !inst.isPaid || inst.paidAmountEUR == 0 || inst.amount != item.amount {
                    let payRate = currency == "EUR" ? 1 : (item.paidRate > 0 ? item.paidRate : rates.rate(for: currency))
                    inst.markPaid(rateEURPerUnit: payRate, date: item.paidDate ?? Date())
                }
            } else if inst.isPaid {
                inst.markUnpaid()
            }
        }
        expense.isSettled = draft.useSchedule ? false : draft.isSettled
    }
}

/// Ligne d'un versement dans l'éditeur.
struct InstallmentDraftRow: View {
    @Binding var draft: InstallmentDraft
    let currency: String
    let travelers: [Traveler]
    let rate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Type", selection: $draft.kind) {
                    ForEach(InstallmentKind.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
                TextField("Montant", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(currency == "EUR" ? "€" : "$").foregroundStyle(.secondary)
            }
            DatePicker("Échéance", selection: $draft.dueDate, displayedComponents: .date)
            Picker("Payeur", selection: $draft.payerID) {
                Text("—").tag(NSManagedObjectID?.none)
                ForEach(travelers, id: \.objectID) { Text($0.wName).tag(NSManagedObjectID?.some($0.objectID)) }
            }
            Toggle(isOn: Binding(get: { draft.isPaid }, set: { paid in
                draft.isPaid = paid
                draft.paidDate = paid ? Date() : nil
                draft.paidRate = paid ? (currency == "EUR" ? 1 : rate) : 0
            })) {
                let status = PaymentMath.status(isPaid: draft.isPaid, dueDate: draft.dueDate)
                Text(status.label).foregroundStyle(status == .overdue ? Color.red : (status == .paid ? Color.green : Color.primary))
            }
            .sensoryFeedback(.success, trigger: draft.isPaid)
        }
        .padding(.vertical, 4)
    }
}
