import Foundation
import CoreData

/// Remise à zéro du stockage local des voyages partagés avec moi.
/// Sans risque : ce stockage ne contient que des copies de voyages qui restent sur l'iCloud
/// de leur organisateur ; ils sont retéléchargés après la remise à zéro.
/// Sert quand un ancien lien d'invitation (ancien conteneur iCloud) a bloqué la synchronisation.
enum SharedStoreReset {
    private static let key = "resetSharedStoreAtNextLaunch"

    static func request() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static var isRequested: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Erreur typique : la zone partagée appartient à un utilisateur d'un autre conteneur.
    static func looksCorrupted(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("Cannot convert userId")
            || text.contains("cannot be used for this container")
    }

    /// À appeler avant le chargement des magasins.
    static func performIfRequested(storeURL: URL, model: NSManagedObjectModel) {
        guard isRequested else { return }
        UserDefaults.standard.set(false, forKey: key)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        do {
            try coordinator.destroyPersistentStore(at: storeURL, type: .sqlite, options: nil)
        } catch {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }
    }
}
