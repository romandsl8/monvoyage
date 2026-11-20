import SwiftUI
import CoreData
import PhotosUI

/// Création / modification d'une dépense, avec moment (avant / pendant le voyage) et échéancier facultatif.
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
    @State private var date = Date()
    @State private var merchant = ""
    @State private var note = ""
    @State private var isPretax = false
    @State private var tax: Double = 0
    @State private var tip: Double = 0
    @State private var receipt: Data?
    @State private var storedRate: Double?
    @State private var originalCurrency: String?
    @State private var reservationID: NSManagedObjectID?
    @State private var activityID: NSManagedObjectID?
    @State private var payment = PaymentDraft()

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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if isPretax || tax > 0 || tip > 0 {
                    Section("Détail") {
                        LabeledContent("Taxe", value: Fmt.money(tax, currency))
                        LabeledContent("Pourboire", value: Fmt.money(tip, currency))
                    }
                }

                PaymentSections(draft: $payment, amount: amount, currency: currency, date: date, trip: trip)

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
            date = expense.date ?? Date()
            merchant = expense.merchant ?? ""
            note = expense.note ?? ""
            isPretax = expense.isPretaxPrice
            tax = expense.taxAmount
            tip = expense.tipAmount
            receipt = expense.receiptImage
            payment = PaymentDraft(expense: expense)
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
            if let name = prefill.categoryName { payment.categoryID = trip.category(named: name)?.objectID }
            if prefill.reservationID != nil { payment.isSettled = false }
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
        if let reservationID, let reservation = try? context.existingObject(with: reservationID) as? Reservation {
            expense.reservation = reservation
        }
        if let activityID, let activity = try? context.existingObject(with: activityID) as? PlanActivity {
            expense.activity = activity
        }
        PaymentSync.apply(payment, to: expense, currency: currency, trip: trip, rates: rates, context: context)
        context.saveIfNeeded()
        savedTick += 1
        dismiss()
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
