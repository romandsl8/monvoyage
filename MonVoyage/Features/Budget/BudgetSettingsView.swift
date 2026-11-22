import SwiftUI

/// Modification rapide du budget d'un voyage déjà créé.
struct BudgetSettingsView: View {
    @ObservedObject var trip: Trip
    var onCategories: (() -> Void)? = nil
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var budget = ""
    @State private var preFees = ""
    @State private var postFees = ""
    @State private var taxPercent = ""
    @State private var tipPercent = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Budget total", text: $budget, currency: "EUR")
                } footer: {
                    Text("Le budget de tout le voyage (vols, hôtel, billets et dépenses sur place). Laissez vide pour utiliser la somme des budgets par catégorie.")
                }
                Section {
                    AmountField(title: "Frais avant départ", text: $preFees, currency: "EUR")
                    AmountField(title: "Frais après retour", text: $postFees, currency: "EUR")
                } header: {
                    Text("Hors séjour")
                } footer: {
                    Text("Parking, trajet vers l'aéroport… exclus du budget restant par jour.")
                }
                Section("Sur place") {
                    AmountField(title: "Taxe locale (%)", text: $taxPercent)
                    AmountField(title: "Pourboire par défaut (%)", text: $tipPercent)
                }
                if let onCategories {
                    Section {
                        Button {
                            dismiss()
                            onCategories()
                        } label: {
                            Label("Budgets par catégorie", systemImage: "square.grid.2x2")
                        }
                    }
                }
            }
            .navigationTitle("Modifier le budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save) }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        budget = trip.totalBudgetEUR > 0 ? Fmt.number(trip.totalBudgetEUR) : ""
        preFees = trip.preDepartureFeesEUR > 0 ? Fmt.number(trip.preDepartureFeesEUR) : ""
        postFees = trip.postDepartureFeesEUR > 0 ? Fmt.number(trip.postDepartureFeesEUR) : ""
        taxPercent = Fmt.number(trip.taxRate * 100, digits: 3)
        tipPercent = Fmt.number(trip.defaultTipRate * 100, digits: 2)
    }

    private func save() {
        trip.totalBudgetEUR = max(0, Money.parse(budget) ?? 0)
        trip.preDepartureFeesEUR = max(0, Money.parse(preFees) ?? 0)
        trip.postDepartureFeesEUR = max(0, Money.parse(postFees) ?? 0)
        if let tax = Money.parse(taxPercent) { trip.taxRate = tax / 100 }
        if let tip = Money.parse(tipPercent) { trip.defaultTipRate = tip / 100 }
        context.saveIfNeeded()
        dismiss()
    }
}
