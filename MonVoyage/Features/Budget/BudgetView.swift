import SwiftUI
import CoreData
import Charts

/// Budget : totaux, graphiques, dépenses.
struct BudgetView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var nav: TripNavigation
    @State private var showCategories = false
    @State private var filterCategory: NSManagedObjectID?

    var body: some View {
        let summary = BudgetSummary(trip: trip)
        ScrollView {
            VStack(spacing: 16) {
                totals(summary)
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        donut(summary)
                        bars(summary)
                    }
                } else {
                    donut(summary)
                    bars(summary)
                }
                expensesList
            }
            .padding()
            .padding(.bottom, 80)   // place pour le bouton « + » flottant
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .groupedBackground()
        .navigationTitle("Budget")
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton(label: "Ajouter une dépense") {
                nav.present(.newExpense(ExpensePrefill(currency: trip.isOngoing() ? trip.currencyCode : "EUR")))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { nav.present(.scanReceipt) } label: { Label("Scanner un ticket", systemImage: "doc.viewfinder") }
                    Button { nav.open(.dueDates) } label: { Label("Échéances", systemImage: "calendar.badge.clock") }
                    Button { showCategories = true } label: { Label("Catégories et budgets", systemImage: "square.grid.2x2") }
                } label: { Label("Options", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showCategories) { CategoriesEditorView(trip: trip) }
    }

    private func totals(_ s: BudgetSummary) -> some View {
        Card {
            CardTitle(title: "Vue d'ensemble", symbol: "eurosign.circle.fill", tint: trip.accent)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { totalItems(s) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) { totalItems(s) }
            }
            if s.budgetEUR > 0 {
                ProgressBar(fraction: s.consumedFraction, tint: trip.accent)
                Text(s.gapEUR >= 0 ? "Marge de \(Fmt.eur(s.gapEUR)) sur le budget de \(Fmt.eur(s.budgetEUR))"
                                   : "Dépassement de \(Fmt.eur(-s.gapEUR)) sur le budget de \(Fmt.eur(s.budgetEUR))")
                    .font(.caption).foregroundStyle(s.gapEUR >= 0 ? Color.secondary : Color.red)
            }
            if let next = s.nextDue, let due = next.dueDate {
                Divider()
                HStack {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(next.computedStatus == .overdue ? .red : trip.accent)
                    VStack(alignment: .leading) {
                        Text("Prochaine échéance : \(Fmt.day(due))").font(.subheadline.weight(.semibold))
                        Text("\(Fmt.money(next.amount, next.currencyCode)) · \(next.expense?.wTitle ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func totalItems(_ s: BudgetSummary) -> some View {
        BigNumber(label: "Prévu", value: Fmt.eurShort(s.plannedEUR))
        BigNumber(label: "Payé", value: Fmt.eurShort(s.paidEUR), tint: .green)
        BigNumber(label: "Reste à payer", value: Fmt.eurShort(s.remainingEUR), tint: .orange)
        BigNumber(label: "Écart au budget", value: Fmt.eurShort(s.gapEUR), tint: s.gapEUR >= 0 ? .primary : .red)
    }

    private func donut(_ s: BudgetSummary) -> some View {
        Card {
            CardTitle(title: "Répartition", symbol: "chart.pie.fill", tint: trip.accent)
            let data = s.categories.filter { $0.spentEUR > 0 }
            if data.isEmpty {
                Text("Aucune dépense pour l'instant.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(data) { line in
                    SectorMark(angle: .value("Montant", line.spentEUR), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(by: .value("Catégorie", line.name))
                        .cornerRadius(4)
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .frame(height: 240)
                .accessibilityLabel("Répartition des dépenses par catégorie")
            }
        }
    }

    private func bars(_ s: BudgetSummary) -> some View {
        Card {
            CardTitle(title: "Prévu et dépensé", symbol: "chart.bar.fill", tint: trip.accent)
            let data = s.categories.filter { $0.spentEUR > 0 || $0.plannedBudgetEUR > 0 }
            if data.isEmpty {
                Text("Définissez des budgets par catégorie depuis le menu ⋯.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(data) { line in
                        BarMark(x: .value("Montant", line.plannedBudgetEUR), y: .value("Catégorie", line.name))
                            .foregroundStyle(by: .value("Type", "Budget prévu"))
                            .position(by: .value("Type", "Budget prévu"))
                        BarMark(x: .value("Montant", line.spentEUR), y: .value("Catégorie", line.name))
                            .foregroundStyle(by: .value("Type", "Dépensé"))
                            .position(by: .value("Type", "Dépensé"))
                    }
                }
                .chartForegroundStyleScale(["Budget prévu": Color.secondary.opacity(0.4), "Dépensé": trip.accent])
                .frame(height: CGFloat(max(160, data.count * 48)))
            }
        }
    }

    private var filteredExpenses: [Expense] {
        guard let filterCategory else { return trip.expenseList }
        return trip.expenseList.filter { $0.category?.objectID == filterCategory }
    }

    private var expensesList: some View {
        Card {
            HStack {
                CardTitle(title: "Dépenses", symbol: "list.bullet", tint: trip.accent)
                Spacer()
                Menu {
                    Button("Toutes") { filterCategory = nil }
                    ForEach(trip.categoryList, id: \.objectID) { cat in
                        Button(cat.name ?? "") { filterCategory = cat.objectID }
                    }
                } label: {
                    Label("Filtrer", systemImage: "line.3.horizontal.decrease.circle").labelStyle(.iconOnly)
                }
            }
            if filteredExpenses.isEmpty {
                EmptyState(symbol: "eurosign.circle", title: "Aucune dépense",
                           message: "Ajoutez une dépense, scannez un ticket ou utilisez Siri.",
                           actionTitle: "Ajouter") { nav.present(.newExpense(ExpensePrefill())) }
            } else {
                ForEach(filteredExpenses, id: \.objectID) { expense in
                    Button { nav.present(.editExpense(expense.objectID)) } label: {
                        ExpenseRow(expense: expense)
                    }
                    .buttonStyle(.plain)
                    if expense != filteredExpenses.last { Divider() }
                }
            }
        }
    }
}

struct ExpenseRow: View {
    @ObservedObject var expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category?.symbol ?? "tag.fill")
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(expense.wTitle).font(.body).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Fmt.money(expense.amount, expense.currencyCode))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 4) {
                    Text(detailLine)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if expense.receiptImage != nil {
                        Image(systemName: "paperclip").accessibilityLabel("Ticket joint")
                    }
                    Spacer(minLength: 4)
                    if expense.currencyCode != "EUR" {
                        Text(Fmt.eur(expense.amountEUR)).monospacedDigit().lineLimit(1).fixedSize()
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// « ven. 20 nov. · Soldé » sur une seule ligne.
    private var detailLine: String {
        [expense.date.map { Fmt.day($0) }, expense.status.label].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Catégories modifiables, budget prévu, « avant départ ».
struct CategoriesEditorView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(trip.categoryList, id: \.objectID) { cat in
                        CategoryRow(category: cat)
                    }
                    .onMove { from, to in
                        var list = trip.categoryList
                        list.move(fromOffsets: from, toOffset: to)
                        for (i, c) in list.enumerated() { c.sortIndex = Int32(i) }
                        context.saveIfNeeded()
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(trip.categoryList[i]) }
                        context.saveIfNeeded()
                    }
                } footer: {
                    Text("« Avant départ » : dépenses réglées avant le séjour (vols, hôtel, billets…), exclues du budget restant par jour.")
                }
                Section {
                    HStack {
                        TextField("Nouvelle catégorie", text: $newName)
                        Button("Ajouter") {
                            let c = context.make(BudgetCategory.self, trip: trip)
                            c.name = newName
                            c.symbol = "tag.fill"
                            c.sortIndex = Int32(trip.categoryList.count)
                            c.trip = trip
                            context.saveIfNeeded()
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Catégories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { context.saveIfNeeded(); dismiss() } }
            }
        }
    }
}

struct CategoryRow: View {
    @ObservedObject var category: BudgetCategory
    @State private var budgetText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: category.symbol ?? "tag.fill").foregroundStyle(Color.accentColor)
                TextField("Nom", text: Binding(get: { category.name ?? "" }, set: { category.name = $0 }))
            }
            AmountField(title: "Budget prévu", text: $budgetText, currency: "EUR")
                .onChange(of: budgetText) { _, text in category.plannedEUR = Money.parse(text) ?? 0 }
            Toggle("Avant départ", isOn: Binding(get: { category.isPreDeparture }, set: { category.isPreDeparture = $0 }))
                .font(.subheadline)
        }
        .onAppear { budgetText = category.plannedEUR > 0 ? Fmt.number(category.plannedEUR) : "" }
    }
}
