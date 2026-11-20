import AppIntents
import CoreData

enum CurrencyOption: String, AppEnum {
    case usd, eur

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Devise"
    static var caseDisplayRepresentations: [CurrencyOption: DisplayRepresentation] = [
        .usd: DisplayRepresentation(title: "dollars", synonyms: ["dollar", "USD", "$"]),
        .eur: DisplayRepresentation(title: "euros", synonyms: ["euro", "EUR", "€"])
    ]

    var code: String { self == .usd ? "USD" : "EUR" }
}

enum CategoryOption: String, AppEnum {
    case repas, transport, shopping, souvenirs, divers, parcs, express, hebergement, vols

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Catégorie"
    static var caseDisplayRepresentations: [CategoryOption: DisplayRepresentation] = [
        .repas: DisplayRepresentation(title: "repas", synonyms: ["restaurant", "nourriture", "manger"]),
        .transport: DisplayRepresentation(title: "transport", synonyms: ["taxi", "uber", "essence"]),
        .shopping: DisplayRepresentation(title: "shopping", synonyms: ["achats", "courses"]),
        .souvenirs: DisplayRepresentation(title: "souvenirs", synonyms: ["souvenir", "cadeaux"]),
        .divers: DisplayRepresentation(title: "divers", synonyms: ["autre"]),
        .parcs: DisplayRepresentation(title: "billets parcs", synonyms: ["parc", "billets"]),
        .express: DisplayRepresentation(title: "Express Pass", synonyms: ["express"]),
        .hebergement: DisplayRepresentation(title: "hébergement", synonyms: ["hôtel", "hotel"]),
        .vols: DisplayRepresentation(title: "vols", synonyms: ["avion", "vol"])
    ]

    var categoryName: String {
        switch self {
        case .repas: return "Repas"
        case .transport: return "Transport"
        case .shopping: return "Shopping"
        case .souvenirs: return "Souvenirs"
        case .divers: return "Divers"
        case .parcs: return "Billets parcs"
        case .express: return "Express Pass"
        case .hebergement: return "Hébergement"
        case .vols: return "Vols"
        }
    }
}

/// « Dis Siri, ajoute une dépense dans MonVoyage » → montant, devise, catégorie.
/// La dépense va dans le voyage en cours, sinon le prochain à venir.
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter une dépense"
    static var description = IntentDescription("Ajoute une dépense au voyage en cours, ou au prochain voyage.")

    @Parameter(title: "Montant", requestValueDialog: "Quel montant ?")
    var amount: Double

    @Parameter(title: "Devise", default: .usd)
    var currency: CurrencyOption

    @Parameter(title: "Catégorie", default: .repas)
    var category: CategoryOption

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$amount) \(\.$currency) en \(\.$category)")
    }

    init() {}

    init(amount: Double, currency: CurrencyOption, category: CategoryOption) {
        self.amount = amount
        self.currency = currency
        self.category = category
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.viewContext
        guard let trip = TripFactory.currentOrNextTrip(in: context) else {
            return .result(dialog: "Aucun voyage en cours ou à venir dans MonVoyage.")
        }
        let rates = ExchangeRateService.shared
        await rates.refreshIfNeeded()
        let code = currency.code
        let rate = rates.rate(for: code)
        let expense = context.make(Expense.self, trip: trip)
        expense.trip = trip
        expense.title = category.categoryName
        expense.amount = amount
        expense.currency = code
        expense.rateUsed = rate
        expense.amountEUR = Money.toEUR(amount, currency: code, rateEURPerUnit: rate)
        expense.date = Date()
        expense.isSettled = true
        expense.category = trip.category(named: category.categoryName)
        context.saveIfNeeded()
        WidgetSnapshotWriter.update(context: context)

        let shown = Fmt.money(amount, code)
        let euros = code == "EUR" ? "" : " (\(Fmt.eur(expense.amountEUR)))"
        return .result(dialog: "\(shown)\(euros) ajoutés en \(category.categoryName) dans \(trip.wName).")
    }
}

struct MonVoyageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Ajoute une dépense dans \(.applicationName)",
                "Ajoute une dépense en \(\.$category) dans \(.applicationName)",
                "Nouvelle dépense \(.applicationName)",
                "Ajoute des \(\.$currency) dans \(.applicationName)"
            ],
            shortTitle: "Ajouter une dépense",
            systemImageName: "eurosign.circle.fill"
        )
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: ["Ajout express dans \(.applicationName)"],
            shortTitle: "Ajout express",
            systemImageName: "plus.circle.fill"
        )
    }
}
