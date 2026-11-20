import SwiftUI
import CoreData
import PhotosUI

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

/// Création / modification d'une dépense, avec échéancier facultatif.
struct ExpenseEditorView: View {
    @ObservedObject var trip: Trip
    let expenseID: NSManagedObjectID?
    let prefill: ExpensePrefill?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var rates: ExchangeRateService

    @State private var title = ""
    @State private var amountText = ""
    @State private var currency = "EUR"
    @State private var categoryID: NSManagedObjectID?
    @State private var date = Date()
    @State private var payerID: NSManagedObjectID?
    @State private var merchant = ""
    @State private var note = ""
    @State private var isPretax = false
    @State private var tax: Double = 0
    @State private var tip: Double = 0
    @State private var isSettled = true
    @State private var receipt: Data?
    @State private var storedRate: Double?
    @State private var originalCurrency: String?
    @State private var reservationID: NSManagedObjectID?
    @State private var activityID: NSManagedObjectID?

    @State private var useSchedule = false
    @State private var installments: [InstallmentDraft] = []
    @State private var depositText = ""
    @State private var depositIsPercent = false
    @State private var depositDate = Date()
    @State private var splitCount = 3
    @State private var firstInstallmentDate = Date().addingTimeInterval(30 * 86400)

    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var savedTick = 0

    private var amount: Double { Money.parse(amountText) ?? 0 }
    private var rate: Double {
        if currency == "EUR" { return 1 }
        if let storedRate, originalCurrency == currency { return storedRate }
        return rates.rate(for: currency)
    }
    private var amountEUR: Double { Money.toEUR(amount, currency: currency, rateEURPerUnit: rate) }
    private var scheduleGap: Double { PaymentMath.scheduleGap(total: amount, installments: installments.map(\.amount)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Libellé", text: $title)
                    AmountField(title: "Montant", text: $amountText, currency: currency)
                    Picker("Devise", selection: $currency) {
                        Text("Euro (€)").tag("EUR")
                        Text("Dollar ($)").tag("USD")
                    }
                    .pickerStyle(.segmented)
                    if currency != "EUR" && amount > 0 {
                        LabeledContent("En euros", value: Fmt.eur(amountEUR))
                        Text("Taux : 1 $ = \(Fmt.number(rate, digits: 4)) € \(storedRate != nil && originalCurrency == currency ? "(taux de saisie)" : "(taux du jour)")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Catégorie", selection: $categoryID) {
                        Text("Aucune").tag(NSManagedObjectID?.none)
                        ForEach(trip.categoryList, id: \.objectID) { cat in
                            Label(cat.name ?? "", systemImage: cat.symbol ?? "tag").tag(NSManagedObjectID?.some(cat.objectID))
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Payé par", selection: $payerID) {
                        Text("—").tag(NSManagedObjectID?.none)
                        ForEach(trip.travelerList, id: \.objectID) { t in
                            Text(t.wName).tag(NSManagedObjectID?.some(t.objectID))
                        }
                    }
                }

                if isPretax || tax > 0 || tip > 0 {
                    Section("Détail") {
                        LabeledContent("Taxe", value: Fmt.money(tax, currency))
                        LabeledContent("Pourboire", value: Fmt.money(tip, currency))
                    }
                }

                Section {
                    Toggle("Paiement en plusieurs fois", isOn: $useSchedule.animation())
                    if !useSchedule {
                        Toggle("Déjà payée", isOn: $isSettled)
                    }
                } footer: {
                    if !useSchedule && !isSettled { Text("La dépense est comptée comme « prévue » jusqu'à ce qu'elle soit payée.") }
                }

                if useSchedule { scheduleSections }

                Section("Ticket et notes") {
                    TextField("Commerçant", text: $merchant)
                    TextField("Note", text: $note, axis: .vertical)
                    if let receipt, let image = UIImage(data: receipt) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityLabel("Photo du ticket")
                        Button("Retirer la photo", role: .destructive) { self.receipt = nil }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(receipt == nil ? "Joindre une photo" : "Remplacer la photo", systemImage: "photo")
                    }
                }

                if expenseID != nil {
                    Section {
                        Button("Supprimer la dépense", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(expenseID == nil ? "Nouvelle dépense" : "Dépense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(amount <= 0)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        receipt = ImageCompression.jpeg(data)
                    }
                }
            }
            .confirmationDialog("Supprimer cette dépense ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let expenseID, let expense = try? context.existingObject(with: expenseID) {
                        context.delete(expense)
                        context.saveIfNeeded()
                    }
                    dismiss()
                }
            }
            .sensoryFeedback(.success, trigger: savedTick)
        }
    }

    // MARK: Échéancier

    @ViewBuilder
    private var scheduleSections: some View {
        Section {
            HStack {
                AmountField(title: "Acompte", text: $depositText, currency: depositIsPercent ? "%" : currency)
            }
            Toggle("Acompte en pourcentage", isOn: $depositIsPercent)
            DatePicker("Date de l'acompte", selection: $depositDate, displayedComponents: .date)
            Stepper("Solde en \(splitCount) fois", value: $splitCount, in: 1...24)
            DatePicker("1er versement", selection: $firstInstallmentDate, displayedComponents: .date)
            Button {
                generateSchedule()
            } label: {
                Label("Répartir le solde en \(splitCount) fois égales", systemImage: "divide.circle")
            }
            .disabled(amount <= 0)
        } header: {
            Text("Préparer l'échéancier")
        } footer: {
            Text("Un versement par mois à partir du 1er versement. Le reliquat d'arrondi va sur le dernier.")
        }

        Section {
            ForEach($installments) { $draft in
                InstallmentDraftRow(draft: $draft, currency: currency, travelers: trip.travelerList, rate: rates.rate(for: currency))
            }
            .onDelete { installments.remove(atOffsets: $0) }
            .onMove { installments.move(fromOffsets: $0, toOffset: $1) }
            Button {
                installments.append(InstallmentDraft(dueDate: installments.last?.dueDate.addingTimeInterval(30 * 86400) ?? Date()))
            } label: {
                Label("Ajouter un versement", systemImage: "plus.circle")
            }
        } header: {
            Text("Versements")
        } footer: {
            if !installments.isEmpty && abs(scheduleGap) >= 0.01 {
                Label("La somme des versements diffère du total de \(Fmt.money(abs(scheduleGap), currency)) (\(scheduleGap > 0 ? "il manque" : "en trop")).",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if !installments.isEmpty {
                Label("Échéancier cohérent avec le total.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
    }

    private func generateSchedule() {
        let deposit = Money.parse(depositText)
        let plan = PaymentMath.plan(total: amount, deposit: deposit, depositIsPercent: depositIsPercent, depositDate: depositDate,
                                    count: splitCount, firstInstallmentDate: firstInstallmentDate)
        // On conserve les versements déjà payés, on remplace le reste.
        let paid = installments.filter(\.isPaid)
        let fresh = plan.map { p in
            InstallmentDraft(kind: p.kind, amountText: Fmt.number(p.amount), dueDate: p.dueDate, payerID: payerID)
        }
        installments = paid.isEmpty ? fresh : paid + fresh.filter { $0.kind == .installment }
    }

    // MARK: Chargement / sauvegarde

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let expenseID, let expense = try? context.existingObject(with: expenseID) as? Expense {
            title = expense.title ?? ""
            amountText = Fmt.number(expense.amount)
            currency = expense.currencyCode
            originalCurrency = expense.currencyCode
            storedRate = expense.rateUsed
            categoryID = expense.category?.objectID
            date = expense.date ?? Date()
            payerID = expense.paidBy?.objectID
            merchant = expense.merchant ?? ""
            note = expense.note ?? ""
            isPretax = expense.isPretaxPrice
            tax = expense.taxAmount
            tip = expense.tipAmount
            isSettled = expense.isSettled
            receipt = expense.receiptImage
            installments = expense.installmentList.map { inst in
                InstallmentDraft(objectID: inst.objectID, kind: inst.kind, amountText: Fmt.number(inst.amount),
                                 dueDate: inst.dueDate ?? Date(), isPaid: inst.isPaid, paidDate: inst.paidDate,
                                 paidRate: inst.paidRate, payerID: inst.payer?.objectID)
            }
            useSchedule = !installments.isEmpty
        } else if let prefill {
            title = prefill.title
            if let a = prefill.amount { amountText = Fmt.number(a) }
            currency = prefill.currency ?? "EUR"
            date = prefill.date
            merchant = prefill.merchant ?? ""
            isPretax = prefill.isPretax
            tax = prefill.tax
            tip = prefill.tip
            receipt = prefill.receipt
            reservationID = prefill.reservationID
            activityID = prefill.activityID
            if let name = prefill.categoryName { categoryID = trip.category(named: name)?.objectID }
            if prefill.reservationID != nil { isSettled = false }
        }
    }

    private func save() {
        let expense: Expense
        if let expenseID, let existing = try? context.existingObject(with: expenseID) as? Expense {
            expense = existing
        } else {
            expense = context.make(Expense.self, trip: trip)
            expense.trip = trip
        }
        expense.title = title.trimmingCharacters(in: .whitespaces)
        expense.amount = amount
        expense.currency = currency
        expense.rateUsed = rate
        expense.amountEUR = amountEUR
        expense.date = date
        expense.merchant = merchant.isEmpty ? nil : merchant
        expense.note = note.isEmpty ? nil : note
        expense.isPretaxPrice = isPretax
        expense.taxAmount = tax
        expense.tipAmount = tip
        expense.receiptImage = receipt
        expense.category = categoryID.flatMap { try? context.existingObject(with: $0) as? BudgetCategory }
        expense.paidBy = payerID.flatMap { try? context.existingObject(with: $0) as? Traveler }
        if let reservationID, let reservation = try? context.existingObject(with: reservationID) as? Reservation {
            expense.reservation = reservation
        }
        if let activityID, let activity = try? context.existingObject(with: activityID) as? PlanActivity {
            expense.activity = activity
        }

        // Échéancier
        let keep = useSchedule ? installments : []
        let keptIDs = Set(keep.compactMap(\.objectID))
        for existing in expense.installmentList where !keptIDs.contains(existing.objectID) {
            context.delete(existing)
        }
        for (index, draft) in keep.enumerated() {
            let inst: PaymentInstallment
            if let id = draft.objectID, let existing = try? context.existingObject(with: id) as? PaymentInstallment {
                inst = existing
            } else {
                inst = context.make(PaymentInstallment.self, trip: trip)
                inst.expense = expense
            }
            inst.kindRaw = draft.kind.rawValue
            inst.amount = draft.amount
            inst.dueDate = draft.dueDate
            inst.sortIndex = Int32(index)
            inst.payer = draft.payerID.flatMap { try? context.existingObject(with: $0) as? Traveler }
            if draft.isPaid {
                if !inst.isPaid || inst.paidAmountEUR == 0 || inst.amount != draft.amount {
                    let payRate = currency == "EUR" ? 1 : (draft.paidRate > 0 ? draft.paidRate : rates.rate(for: currency))
                    inst.markPaid(rateEURPerUnit: payRate, date: draft.paidDate ?? Date())
                }
            } else if inst.isPaid {
                inst.markUnpaid()
            }
        }
        expense.isSettled = useSchedule ? false : isSettled
        context.saveIfNeeded()
        savedTick += 1
        dismiss()
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

/// Compression des photos jointes (JPEG, côté max 2000 px).
enum ImageCompression {
    static func jpeg(_ data: Data, maxSide: CGFloat = 2000) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7) ?? data
    }
}
