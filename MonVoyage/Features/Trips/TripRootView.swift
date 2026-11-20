import SwiftUI
import CoreData

/// Un voyage ouvert : barre d'onglets (compact) ou barre latérale (large).
/// La mise en page dépend uniquement de la largeur disponible (horizontalSizeClass).
struct TripRootView: View {
    @ObservedObject var trip: Trip
    let onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var router: AppRouter
    @SceneStorage("tripModule") private var storedModule = TripModule.today.rawValue
    @StateObject private var nav = TripNavigation(module: .today)
    @State private var restored = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(trip.accent)
        .environmentObject(nav)
        .sheet(item: $nav.sheet) { sheet in
            sheetContent(sheet)
                .environment(\.managedObjectContext, context)
                .environmentObject(nav)
                .tint(trip.accent)
        }
        .onAppear(perform: restore)
        .onChange(of: nav.module) { _, module in storedModule = module.rawValue }
        .onChange(of: router.quickAddRequested) { _, requested in
            if requested { presentQuickAdd() }
        }
    }

    // MARK: Dispositions

    private var compactLayout: some View {
        TabView(selection: $nav.tab) {
            Tab(TripModule.today.title, systemImage: TripModule.today.symbol, value: TripModule.today) {
                NavigationStack { rootModule(.today) }
            }
            Tab(TripModule.budget.title, systemImage: TripModule.budget.symbol, value: TripModule.budget) {
                NavigationStack { rootModule(.budget) }
            }
            Tab(TripModule.planning.title, systemImage: TripModule.planning.symbol, value: TripModule.planning) {
                NavigationStack { rootModule(.planning) }
            }
            Tab(TripModule.reservations.title, systemImage: TripModule.reservations.symbol, value: TripModule.reservations) {
                NavigationStack { rootModule(.reservations) }
            }
            Tab(TripModule.more.title, systemImage: TripModule.more.symbol, value: TripModule.more) {
                NavigationStack(path: $nav.morePath) {
                    MoreMenuView(trip: trip)
                        .toolbar { closeButton }
                        .navigationDestination(for: TripModule.self) { module in
                            moduleView(module)
                        }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var regularLayout: some View {
        NavigationSplitView {
            // Boutons explicites (plus fiable que la sélection de List dans une barre latérale).
            List {
                Section {
                    ForEach(TripModule.sidebar) { module in
                        let selected = (nav.module == .more ? .today : nav.module) == module
                        Button {
                            nav.open(module)
                        } label: {
                            Label(module.title, systemImage: module.symbol)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? trip.accent : Color.clear)
                                .padding(.horizontal, 8)
                        )
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                } header: {
                    Text(trip.city ?? "")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(trip.wName)
            .toolbar { closeButton }
        } detail: {
            NavigationStack {
                moduleView(nav.module == .more ? .today : nav.module)
            }
        }
    }

    private func rootModule(_ module: TripModule) -> some View {
        moduleView(module).toolbar { closeButton }
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onClose) {
                Label("Mes voyages", systemImage: "square.stack.fill")
            }
            .accessibilityLabel("Retour à la liste des voyages")
        }
    }

    @ViewBuilder
    private func moduleView(_ module: TripModule) -> some View {
        switch module {
        case .today, .more: TodayView(trip: trip)
        case .budget: BudgetView(trip: trip)
        case .dueDates: DueDatesView(trip: trip)
        case .planning: PlanningView(trip: trip)
        case .reservations: ReservationsView(trip: trip)
        case .calculator: CalculatorView(trip: trip)
        case .checklists: ChecklistsView(trip: trip)
        case .parks: ParksView(trip: trip)
        case .tools: ToolsView(trip: trip)
        case .tripSettings: TripSettingsView(trip: trip)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: TripSheet) -> some View {
        switch sheet {
        case .editTrip:
            TripEditorView(trip: trip)
        case .newExpense(let prefill):
            ExpenseEditorView(trip: trip, expenseID: nil, prefill: prefill)
        case .editExpense(let id):
            ExpenseEditorView(trip: trip, expenseID: id, prefill: nil)
        case .scanReceipt:
            ReceiptScanFlow(trip: trip)
        case .newActivity(let day):
            ActivityEditorView(trip: trip, activityID: nil, dayKey: day)
        case .editActivity(let id):
            ActivityEditorView(trip: trip, activityID: id, dayKey: nil)
        case .newReservation(let kind):
            ReservationEditorView(trip: trip, reservationID: nil, kind: kind)
        case .editReservation(let id):
            ReservationEditorView(trip: trip, reservationID: id, kind: .other)
        }
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        if let pending = UserDefaults.standard.string(forKey: "pendingModule"), let module = TripModule(rawValue: pending) {
            UserDefaults.standard.removeObject(forKey: "pendingModule")
            nav.open(module)
        } else if let module = TripModule(rawValue: storedModule) {
            nav.open(module)
        }
        if router.quickAddRequested { presentQuickAdd() }
    }

    private func presentQuickAdd() {
        router.quickAddRequested = false
        nav.present(.newExpense(ExpensePrefill(currency: trip.isOngoing() ? trip.currencyCode : "EUR")))
    }
}

/// Menu « Plus » (format compact).
struct MoreMenuView: View {
    @ObservedObject var trip: Trip

    var body: some View {
        List {
            ForEach(TripModule.secondary) { module in
                NavigationLink(value: module) {
                    Label(module.title, systemImage: module.symbol)
                }
            }
        }
        .navigationTitle(trip.wName)
    }
}
