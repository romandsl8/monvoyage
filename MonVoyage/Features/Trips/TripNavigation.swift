import SwiftUI
import CoreData
import Combine

/// Modules d'un voyage.
enum TripModule: String, CaseIterable, Identifiable, Hashable {
    case today, budget, planning, reservations, more
    case dueDates, calculator, checklists, parks, tools, tripSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .budget: return "Budget"
        case .planning: return "Planning"
        case .reservations: return "Réservations"
        case .more: return "Plus"
        case .dueDates: return "Échéances"
        case .calculator: return "Taxes et pourboire"
        case .checklists: return "Checklists"
        case .parks: return "Parcs et attractions"
        case .tools: return "Outils"
        case .tripSettings: return "Voyage et voyageurs"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.horizon.fill"
        case .budget: return "eurosign.circle.fill"
        case .planning: return "calendar"
        case .reservations: return "doc.text.fill"
        case .more: return "square.grid.2x2.fill"
        case .dueDates: return "calendar.badge.clock"
        case .calculator: return "percent"
        case .checklists: return "checklist"
        case .parks: return "sparkles"
        case .tools: return "wrench.and.screwdriver.fill"
        case .tripSettings: return "person.2.fill"
        }
    }

    /// Couleur propre à chaque module (pastilles d'icônes).
    var color: Color {
        switch self {
        case .today, .more: return .orange
        case .budget: return .green
        case .dueDates: return .red
        case .planning: return .blue
        case .reservations: return .indigo
        case .calculator: return .teal
        case .checklists: return .mint
        case .parks: return .purple
        case .tools: return .gray
        case .tripSettings: return .pink
        }
    }

    /// Courte description (menu « Plus »).
    var subtitle: String {
        switch self {
        case .dueDates: return "Acomptes et versements à venir"
        case .calculator: return "Prix US hors taxe → total"
        case .checklists: return "Valise, documents, à faire"
        case .parks: return "Temps d'attente et ma liste"
        case .tools: return "Horloges et conversions"
        case .tripSettings: return "Partage, passeports, rappels"
        default: return ""
        }
    }

    /// Onglets de la barre du bas (format compact).
    static let tabs: [TripModule] = [.today, .budget, .planning, .reservations, .more]
    /// Modules regroupés sous « Plus ».
    static let secondary: [TripModule] = [.dueDates, .calculator, .checklists, .parks, .tools, .tripSettings]
    /// Barre latérale (format large).
    static let sidebar: [TripModule] = [.today, .budget, .dueDates, .planning, .reservations, .checklists, .parks, .calculator, .tools, .tripSettings]

    var isTab: Bool { TripModule.tabs.contains(self) }
}

/// Pré-remplissage d'une nouvelle dépense (calculateur, scan, réservation, Siri…).
struct ExpensePrefill: Equatable {
    var title: String = ""
    var amount: Double?
    var currency: String?
    var categoryName: String?
    var date: Date = Date()
    var merchant: String?
    var isPretax = false
    var tax: Double = 0
    var tip: Double = 0
    var receipt: Data?
    var reservationID: NSManagedObjectID?
    var activityID: NSManagedObjectID?
}

/// Feuilles présentées au niveau du voyage (au-dessus du choix de mise en page :
/// plier/déplier l'iPhone ne ferme pas une saisie en cours).
enum TripSheet: Identifiable, Equatable {
    case editTrip
    case newExpense(ExpensePrefill)
    case editExpense(NSManagedObjectID)
    case scanReceipt
    case newActivity(String)
    case editActivity(NSManagedObjectID)
    case newReservation(ReservationKind)
    case editReservation(NSManagedObjectID)

    var id: String {
        switch self {
        case .editTrip: return "editTrip"
        case .newExpense: return "newExpense"
        case .editExpense(let id): return "editExpense-\(id.uriRepresentation().absoluteString)"
        case .scanReceipt: return "scan"
        case .newActivity(let day): return "newActivity-\(day)"
        case .editActivity(let id): return "editActivity-\(id.uriRepresentation().absoluteString)"
        case .newReservation(let kind): return "newReservation-\(kind.rawValue)"
        case .editReservation(let id): return "editReservation-\(id.uriRepresentation().absoluteString)"
        }
    }
}

/// État de navigation d'un voyage ouvert (partagé entre disposition compacte et large).
@MainActor
final class TripNavigation: ObservableObject {
    @Published var module: TripModule
    @Published var sheet: TripSheet?
    /// Dernier module secondaire ouvert depuis « Plus ».
    @Published var lastSecondary: TripModule?

    init(module: TripModule) {
        self.module = module
    }

    func open(_ module: TripModule) {
        self.module = module
        if !module.isTab { lastSecondary = module }
    }

    func present(_ sheet: TripSheet) {
        self.sheet = sheet
    }

    /// Onglet sélectionné en format compact.
    var tab: TripModule {
        get { module.isTab ? module : .more }
        set {
            if newValue == .more { module = .more } else { module = newValue }
        }
    }

    /// Pile de navigation de l'onglet « Plus ».
    var morePath: [TripModule] {
        get { module.isTab ? [] : [module] }
        set { module = newValue.last ?? .more }
    }
}
