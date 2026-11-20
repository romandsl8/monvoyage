import WidgetKit
import SwiftUI
import AppIntents

/// Contrôle du Centre de contrôle / bouton Action : ajout express d'une dépense.
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickAddExpenseControl") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Dépense", systemImage: "eurosign.circle.fill")
            }
        }
        .displayName("Ajouter une dépense")
        .description("Ouvre MonVoyage sur l'ajout express d'une dépense.")
    }
}
