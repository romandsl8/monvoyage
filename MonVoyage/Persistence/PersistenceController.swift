import Foundation
import CoreData
import CloudKit

/// Pile Core Data + CloudKit : un magasin privé et un magasin partagé.
///
/// Règles de conservation des données :
/// - la base locale n'est JAMAIS supprimée ni recréée par le code ;
/// - une copie `.backup` est faite avant chaque chargement ;
/// - en cas d'échec, rien n'est effacé : `loadError` est renseigné et l'appli
///   affiche un écran d'erreur avec export de la sauvegarde.
final class PersistenceController {
    static let shared = PersistenceController(inMemory: PersistenceController.isRunningTests)

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var cloudKitContainerID: String {
        (Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerID") as? String) ?? "iCloud.fr.tanguy.monvoyage"
    }

    /// Modèle chargé une seule fois (évite les doublons d'entités dans les tests).
    static let model: NSManagedObjectModel = {
        let bundle = Bundle(for: PersistenceController.self)
        guard let url = bundle.url(forResource: "MonVoyage", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Modèle Core Data MonVoyage introuvable dans le bundle.")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer
    let inMemory: Bool
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private(set) var loadError: Error?

    var viewContext: NSManagedObjectContext { container.viewContext }

    static var storeDirectory: URL {
        NSPersistentContainer.defaultDirectoryURL()
    }
    static var privateStoreURL: URL { storeDirectory.appendingPathComponent("MonVoyage.sqlite") }
    static var sharedStoreURL: URL { storeDirectory.appendingPathComponent("MonVoyage-shared.sqlite") }

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        container = NSPersistentCloudKitContainer(name: "MonVoyage", managedObjectModel: Self.model)

        if inMemory {
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null").appendingPathComponent(UUID().uuidString))
            description.type = NSInMemoryStoreType
            description.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [description]
        } else {
            StoreBackup.backupBeforeLoading(storeURLs: [Self.privateStoreURL, Self.sharedStoreURL])

            let privateDesc = NSPersistentStoreDescription(url: Self.privateStoreURL)
            configure(privateDesc, scope: .private)
            let sharedDesc = NSPersistentStoreDescription(url: Self.sharedStoreURL)
            configure(sharedDesc, scope: .shared)
            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        }

        if !inMemory { SyncEventLog.shared.start(self) }
        var firstError: Error?
        container.loadPersistentStores { description, error in
            if let error {
                if firstError == nil { firstError = error }
                return
            }
            if let options = description.cloudKitContainerOptions, options.databaseScope == .shared {
                self.sharedStore = self.container.persistentStoreCoordinator.persistentStore(for: description.url!)
            } else {
                self.privateStore = self.container.persistentStoreCoordinator.persistentStore(for: description.url!)
            }
        }
        if inMemory, privateStore == nil {
            privateStore = container.persistentStoreCoordinator.persistentStores.first
        }
        loadError = firstError

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
        container.viewContext.name = "viewContext"
        Self.register(self)
    }

    private func configure(_ description: NSPersistentStoreDescription, scope: CKDatabase.Scope) {
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
    }

    // MARK: - Schéma CloudKit (écran caché)

    /// Crée le schéma dans l'environnement CloudKit *Development*.
    /// Ne fonctionne que si l'entitlement `icloud-container-environment` vaut Development.
    func initializeCloudKitSchema() throws {
        try container.initializeCloudKitSchema(options: [])
    }

    // MARK: - Utilitaires

    /// Magasin dans lequel ranger un nouvel objet rattaché à `trip`.
    func store(for trip: Trip?) -> NSPersistentStore? {
        if let store = trip?.objectID.persistentStore { return store }
        return privateStore
    }

    func isShared(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }
}

// MARK: - Création et sauvegarde

extension NSManagedObjectContext {
    /// Crée un objet avec id / createdAt / updatedAt, rangé dans le même magasin que le voyage
    /// (indispensable pour les voyages partagés : un objet ne peut pas relier deux magasins).
    func make<T: NSManagedObject>(_ type: T.Type, trip: Trip?) -> T {
        // Les noms d'entités sont identiques aux noms de classes.
        let entityName = String(describing: T.self)
        guard let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: self) as? T else {
            fatalError("Entité Core Data introuvable : \(entityName)")
        }
        let now = Date()
        if object.entity.attributesByName["id"] != nil { object.setValue(UUID(), forKey: "id") }
        if object.entity.attributesByName["createdAt"] != nil { object.setValue(now, forKey: "createdAt") }
        if object.entity.attributesByName["updatedAt"] != nil { object.setValue(now, forKey: "updatedAt") }
        let controller = PersistenceController.controller(for: self)
        if let store = controller?.store(for: trip) {
            assign(object, to: store)
        }
        return object
    }

    /// Sauvegarde en mettant à jour `updatedAt`. Les erreurs sont journalisées, jamais fatales.
    @discardableResult
    func saveIfNeeded() -> Bool {
        guard hasChanges else { return true }
        let now = Date()
        for object in updatedObjects.union(insertedObjects) where !object.isDeleted {
            if object.entity.attributesByName["updatedAt"] != nil, object.changedValues()["updatedAt"] == nil {
                object.setValue(now, forKey: "updatedAt")
            }
        }
        do {
            try save()
            NotificationCenter.default.post(name: .monVoyageDataDidChange, object: nil)
            return true
        } catch {
            print("Erreur de sauvegarde Core Data : \(error)")
            return false
        }
    }
}

extension PersistenceController {
    /// Retrouve le contrôleur propriétaire d'un contexte (shared ou contrôleur de test).
    private static var registry: [ObjectIdentifier: PersistenceController] = [:]

    static func register(_ controller: PersistenceController) {
        registry[ObjectIdentifier(controller.container.persistentStoreCoordinator)] = controller
    }

    static func controller(for context: NSManagedObjectContext) -> PersistenceController? {
        guard let coordinator = context.persistentStoreCoordinator else { return nil }
        if let found = registry[ObjectIdentifier(coordinator)] { return found }
        if coordinator === shared.container.persistentStoreCoordinator { return shared }
        return nil
    }
}

extension Notification.Name {
    static let monVoyageDataDidChange = Notification.Name("monVoyageDataDidChange")
}
