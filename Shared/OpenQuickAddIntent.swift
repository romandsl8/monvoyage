import Foundation
import AppIntents

/// Intention utilisée par le contrôle du Centre de contrôle (et le bouton Action) :
/// ouvre l'appli directement sur l'ajout express d'une dépense.
/// Ce fichier est compilé dans l'appli ET dans l'extension widget.
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajout express d'une dépense"
    static var description = IntentDescription("Ouvre MonVoyage sur l'ajout rapide d'une dépense.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.pendingQuickAdd)
        return .result()
    }
}
