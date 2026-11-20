import SwiftUI
import Combine

/// État global de navigation (survit aux changements de mise en page plié / déplié).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Demande d'ajout express (contrôle, bouton Action, lien monvoyage://quickadd).
    @Published var quickAddRequested = false
    /// Archive .zip ouverte depuis Fichiers / AirDrop.
    @Published var pendingImportURL: URL?
    @Published var alertMessage: String?

    func checkPendingQuickAdd() {
        let stamp = AppGroup.defaults.double(forKey: SharedKeys.pendingQuickAdd)
        guard stamp > 0 else { return }
        AppGroup.defaults.removeObject(forKey: SharedKeys.pendingQuickAdd)
        if Date().timeIntervalSince1970 - stamp < 120 { quickAddRequested = true }
    }

    func handle(url: URL) {
        if url.scheme == "monvoyage" {
            if url.host == "quickadd" { quickAddRequested = true }
            return
        }
        if url.pathExtension.lowercased() == "zip" { pendingImportURL = url }
    }
}
