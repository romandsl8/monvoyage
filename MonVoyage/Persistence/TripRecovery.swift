import Foundation
import CoreData
import CloudKit
import SwiftUI

/// Récupération de voyages : depuis une copie de sécurité de la base sur l'iPhone,
/// ou depuis l'ancien conteneur iCloud. Les voyages sont recopiés (jamais déplacés) dans la
/// base actuelle ; un voyage déjà présent (même identifiant) n'est pas recopié.
enum TripRecovery {
    static let oldContainerID = "iCloud.fr.tanguy.monvoyage"

    struct FoundTrip: Identifiable {
        let id: String
        let name: String
        let start: Date?
        let end: Date?
        let items: Int
        let alreadyPresent: Bool
        let tripUUID: UUID?
    }

    static func presentTripIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        let trips = (try? context.fetch(request)) ?? []
        return Set(trips.compactMap { $0.value(forKey: "id") as? UUID })
    }

    // MARK: - Copie de sécurité locale

    /// Ouvre une copie (dupliquée dans un dossier temporaire, la copie d'origine n'est pas touchée).
    static func openBackup(_ set: StoreBackup.BackupSet) throws -> NSPersistentContainer? {
        guard set.files["MonVoyage.sqlite"] != nil else { return nil }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Recuperation-\(set.id)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["MonVoyage.sqlite", "MonVoyage.sqlite-wal", "MonVoyage.sqlite-shm"] {
            if let source = set.files[name] { try fm.copyItem(at: source, to: dir.appendingPathComponent(name)) }
        }
        let container = NSPersistentContainer(name: "Recuperation", managedObjectModel: PersistenceController.model)
        let description = NSPersistentStoreDescription(url: dir.appendingPathComponent("MonVoyage.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    /// Objets reliés au voyage (dans la même base).
    static func graph(of root: NSManagedObject) -> [NSManagedObject] {
        var seen = Set<NSManagedObjectID>()
        var order: [NSManagedObject] = []
        var queue: [NSManagedObject] = [root]
        while let object = queue.popLast() {
            guard !object.isDeleted, seen.insert(object.objectID).inserted else { continue }
            order.append(object)
            for (name, relationship) in object.entity.relationshipsByName {
                let value = object.value(forKey: name)
                if relationship.isToMany {
                    if let set = value as? NSSet { queue += set.allObjects.compactMap { $0 as? NSManagedObject } }
                    if let set = value as? NSOrderedSet { queue += set.array.compactMap { $0 as? NSManagedObject } }
                } else if let other = value as? NSManagedObject {
                    queue.append(other)
                }
            }
        }
        return order
    }

    static func trips(in container: NSPersistentContainer, present: Set<UUID>) -> [FoundTrip] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        let trips = (try? container.viewContext.fetch(request)) ?? []
        return trips.map { trip in
            let uuid = trip.value(forKey: "id") as? UUID
            return FoundTrip(id: trip.objectID.uriRepresentation().absoluteString,
                             name: (trip.value(forKey: "name") as? String) ?? "Voyage sans nom",
                             start: trip.value(forKey: "startDate") as? Date,
                             end: trip.value(forKey: "endDate") as? Date,
                             items: graph(of: trip).count,
                             alreadyPresent: uuid.map { present.contains($0) } ?? false,
                             tripUUID: uuid)
        }
    }

    /// Recopie un voyage d'une copie de sécurité dans la base actuelle (magasin privé).
    @discardableResult
    static func restore(tripURI: String, from container: NSPersistentContainer) throws -> Int {
        let controller = PersistenceController.shared
        guard let store = controller.privateStore,
              let url = URL(string: tripURI),
              let id = container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) else {
            throw RecoveryError.notFound
        }
        let source = try container.viewContext.existingObject(with: id)
        let dest = controller.viewContext
        let objects = graph(of: source)
        var map: [NSManagedObjectID: NSManagedObject] = [:]
        for object in objects {
            guard let entityName = object.entity.name else { continue }
            let copy = NSEntityDescription.insertNewObject(forEntityName: entityName, into: dest)
            dest.assign(copy, to: store)
            for name in object.entity.attributesByName.keys {
                copy.setValue(object.value(forKey: name), forKey: name)
            }
            map[object.objectID] = copy
        }
        for object in objects {
            guard let copy = map[object.objectID] else { continue }
            for (name, relationship) in object.entity.relationshipsByName where !relationship.isToMany {
                if let other = object.value(forKey: name) as? NSManagedObject, let target = map[other.objectID] {
                    copy.setValue(target, forKey: name)
                }
            }
        }
        guard dest.saveIfNeeded() else { throw RecoveryError.saveFailed }
        return objects.count
    }

    enum RecoveryError: LocalizedError {
        case notFound, saveFailed
        var errorDescription: String? {
            switch self {
            case .notFound: return "voyage introuvable dans cette source"
            case .saveFailed: return "enregistrement impossible dans la base actuelle"
            }
        }
    }

    // MARK: - Ancien conteneur iCloud

    /// Enregistrement Core Data lu sur iCloud (valeurs déjà téléchargées).
    struct CloudObject {
        let recordName: String
        let entity: String
        let modified: Date
        var values: [String: Any]
    }

    static func fetchOldCloud() async throws -> (objects: [String: CloudObject], notes: [String]) {
        let database = CKContainer(identifier: oldContainerID).privateCloudDatabase
        let zones = try await database.allRecordZones()
        var objects: [String: CloudObject] = [:]
        var notes: [String] = []
        // La zone par défaut d'iCloud ne se lit pas par « changements » et ne contient pas
        // les données Core Data (rangées dans com.apple.coredata.cloudkit.zone et les zones de partage).
        for zone in zones where zone.zoneID.zoneName != CKRecordZone.ID.defaultZoneName {
            let before = objects.count
            do {
                try await fetchZone(zone.zoneID, in: database, into: &objects)
                notes.append("Zone \(zone.zoneID.zoneName) : \(objects.count - before) éléments lus.")
            } catch {
                let code = (error as? CKError).map { " [code \($0.errorCode)]" } ?? ""
                notes.append("Zone \(zone.zoneID.zoneName) illisible\(code) : \(error.localizedDescription)")
            }
        }
        return (objects, notes)
    }

    private static func fetchZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase,
                                  into objects: inout [String: CloudObject]) async throws {
        do {
            var token: CKServerChangeToken?
            var more = true
            while more {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token,
                                                                   desiredKeys: nil, resultsLimit: nil)
                for (_, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result else { continue }
                    let record = modification.record
                    guard record.recordType.hasPrefix("CD_") else { continue }
                    var values: [String: Any] = [:]
                    for key in record.allKeys() {
                        if let asset = record[key] as? CKAsset {
                            if let url = asset.fileURL, let data = try? Data(contentsOf: url) { values[key] = data }
                        } else if let value = record[key] {
                            values[key] = value
                        }
                    }
                    let entity = (values["CD_entityName"] as? String) ?? String(record.recordType.dropFirst(3))
                    let object = CloudObject(recordName: record.recordID.recordName, entity: entity,
                                             modified: record.modificationDate ?? .distantPast, values: values)
                    if let existing = objects[object.recordName], existing.modified > object.modified { continue }
                    objects[object.recordName] = object
                }
                token = changes.changeToken
                more = changes.moreComing
            }
        }
    }

    /// Enregistrements reliés à un voyage (par les relations « vers un »).
    static func component(of tripRecord: String, in objects: [String: CloudObject]) -> [CloudObject] {
        let model = PersistenceController.model
        var edges: [String: Set<String>] = [:]
        for object in objects.values {
            guard let entity = model.entitiesByName[object.entity] else { continue }
            for (name, relationship) in entity.relationshipsByName where !relationship.isToMany {
                if let target = object.values["CD_\(name)"] as? String, objects[target] != nil {
                    edges[object.recordName, default: []].insert(target)
                    edges[target, default: []].insert(object.recordName)
                }
            }
        }
        var seen: Set<String> = []
        var queue = [tripRecord]
        while let name = queue.popLast() {
            guard seen.insert(name).inserted else { continue }
            queue += edges[name] ?? []
        }
        return seen.compactMap { objects[$0] }
    }

    static func cloudTrips(_ objects: [String: CloudObject], present: Set<UUID>) -> [FoundTrip] {
        objects.values.filter { $0.entity == "Trip" }.map { trip in
            let uuid = (trip.values["CD_id"] as? String).flatMap(UUID.init(uuidString:))
            return FoundTrip(id: trip.recordName,
                             name: (trip.values["CD_name"] as? String) ?? "Voyage sans nom",
                             start: trip.values["CD_startDate"] as? Date,
                             end: trip.values["CD_endDate"] as? Date,
                             items: component(of: trip.recordName, in: objects).count,
                             alreadyPresent: uuid.map { present.contains($0) } ?? false,
                             tripUUID: uuid)
        }
    }

    private static func value(_ object: CloudObject, name: String, type: NSAttributeType) -> Any? {
        var raw = object.values["CD_\(name)"]
        if raw == nil, let data = object.values["CD_\(name)_ckAsset"] as? Data {
            raw = type == .stringAttributeType ? String(data: data, encoding: .utf8) : data
        }
        guard let raw else { return nil }
        switch type {
        case .stringAttributeType: return raw as? String
        case .UUIDAttributeType: return (raw as? String).flatMap(UUID.init(uuidString:)) ?? (raw as? UUID)
        case .URIAttributeType: return (raw as? String).flatMap(URL.init(string:))
        case .decimalAttributeType: return (raw as? String).map { NSDecimalNumber(string: $0) } ?? (raw as? NSNumber)
        case .dateAttributeType: return raw as? Date
        case .doubleAttributeType, .floatAttributeType, .integer16AttributeType,
             .integer32AttributeType, .integer64AttributeType: return raw as? NSNumber
        case .booleanAttributeType: return (raw as? NSNumber).map { NSNumber(value: $0.boolValue) }
        case .binaryDataAttributeType: return raw as? Data
        default: return nil
        }
    }

    /// Recopie un voyage de l'ancien iCloud dans la base actuelle (magasin privé).
    @discardableResult
    static func restore(cloudTrip recordName: String, from objects: [String: CloudObject]) throws -> Int {
        let controller = PersistenceController.shared
        guard let store = controller.privateStore else { throw RecoveryError.saveFailed }
        let dest = controller.viewContext
        let model = PersistenceController.model
        let records = component(of: recordName, in: objects)
        guard !records.isEmpty else { throw RecoveryError.notFound }
        var map: [String: NSManagedObject] = [:]
        for record in records {
            guard let entity = model.entitiesByName[record.entity], let entityName = entity.name else { continue }
            let copy = NSEntityDescription.insertNewObject(forEntityName: entityName, into: dest)
            dest.assign(copy, to: store)
            for (name, attribute) in entity.attributesByName {
                if let v = value(record, name: name, type: attribute.attributeType) { copy.setValue(v, forKey: name) }
            }
            map[record.recordName] = copy
        }
        for record in records {
            guard let copy = map[record.recordName], let entity = model.entitiesByName[record.entity] else { continue }
            for (name, relationship) in entity.relationshipsByName where !relationship.isToMany {
                if let target = record.values["CD_\(name)"] as? String, let other = map[target] {
                    copy.setValue(other, forKey: name)
                }
            }
        }
        guard dest.saveIfNeeded() else { throw RecoveryError.saveFailed }
        return map.count
    }
}

// MARK: - Écran

@MainActor
final class TripRecoveryModel: ObservableObject {
    struct BackupSource: Identifiable {
        let id: String
        let label: String
        let container: NSPersistentContainer?
        var trips: [TripRecovery.FoundTrip]
        let error: String?
    }

    @Published var backups: [BackupSource] = []
    @Published var cloudTrips: [TripRecovery.FoundTrip] = []
    @Published var cloudStatus: String?
    @Published var loadingCloud = false
    @Published var message: String?
    private var cloudObjects: [String: TripRecovery.CloudObject] = [:]

    private var present: Set<UUID> { TripRecovery.presentTripIDs(in: PersistenceController.shared.viewContext) }

    func loadBackups() {
        let present = self.present
        backups = StoreBackup.backupSets().map { set in
            do {
                guard let container = try TripRecovery.openBackup(set) else {
                    return BackupSource(id: set.id, label: set.label, container: nil, trips: [], error: "pas de base dans cette copie")
                }
                return BackupSource(id: set.id, label: set.label, container: container,
                                    trips: TripRecovery.trips(in: container, present: present), error: nil)
            } catch {
                return BackupSource(id: set.id, label: set.label, container: nil, trips: [], error: error.localizedDescription)
            }
        }
    }

    func loadCloud() async {
        loadingCloud = true
        defer { loadingCloud = false }
        do {
            let result = try await TripRecovery.fetchOldCloud()
            cloudObjects = result.objects
            cloudTrips = TripRecovery.cloudTrips(cloudObjects, present: present)
            let notes = result.notes.isEmpty ? "Aucune zone de données dans l'ancien iCloud." : result.notes.joined(separator: "\n")
            cloudStatus = (cloudTrips.isEmpty ? "Aucun voyage trouvé dans l'ancien iCloud.\n" : "") + notes
        } catch {
            let code = (error as? CKError).map { " [code \($0.errorCode)]" } ?? ""
            cloudStatus = "Ancien iCloud illisible\(code) : \(error.localizedDescription)"
        }
    }

    func restore(_ trip: TripRecovery.FoundTrip, from source: BackupSource) {
        guard let container = source.container else { return }
        do {
            let n = try TripRecovery.restore(tripURI: trip.id, from: container)
            message = "« \(trip.name) » est récupéré (\(n) éléments). Il est de retour dans Mes voyages."
            refreshPresence()
        } catch {
            message = "Récupération impossible : \(error.localizedDescription)"
        }
    }

    func restoreCloud(_ trip: TripRecovery.FoundTrip) {
        do {
            let n = try TripRecovery.restore(cloudTrip: trip.id, from: cloudObjects)
            message = "« \(trip.name) » est récupéré depuis l'ancien iCloud (\(n) éléments). Il est de retour dans Mes voyages."
            refreshPresence()
        } catch {
            message = "Récupération impossible : \(error.localizedDescription)"
        }
    }

    private func refreshPresence() {
        let present = self.present
        backups = backups.map { source in
            var copy = source
            if let container = source.container { copy.trips = TripRecovery.trips(in: container, present: present) }
            return copy
        }
        cloudTrips = TripRecovery.cloudTrips(cloudObjects, present: present)
    }
}

struct TripRecoveryView: View {
    @StateObject private var model = TripRecoveryModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let message = model.message {
                    Section { Text(message).font(.callout) }
                }
                Section {
                    if model.loadingCloud {
                        HStack { ProgressView(); Text("Lecture de l'ancien iCloud…").foregroundStyle(.secondary) }
                    }
                    ForEach(model.cloudTrips) { trip in
                        row(trip) { model.restoreCloud(trip) }
                    }
                    if let status = model.cloudStatus { Text(status).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Ancien iCloud") } footer: {
                    Text("Voyages enregistrés sur iCloud avant le changement de conteneur.")
                }
                let withTrips = model.backups.filter { !$0.trips.isEmpty }
                ForEach(withTrips) { source in
                    Section(source.label) {
                        ForEach(source.trips) { trip in
                            row(trip) { model.restore(trip, from: source) }
                        }
                    }
                }
                if withTrips.isEmpty {
                    Section("Copies de sécurité sur cet iPhone") {
                        Text(model.backups.isEmpty ? "Aucune copie de sécurité." : "Aucun voyage dans les \(model.backups.count) copies de sécurité.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Récupérer des voyages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task {
                model.loadBackups()
                await model.loadCloud()
            }
        }
    }

    private func row(_ trip: TripRecovery.FoundTrip, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name).font(.headline)
                Text(details(trip)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if trip.alreadyPresent {
                Label("Présent", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.green)
            } else {
                Button("Récupérer", action: action).buttonStyle(.borderedProminent)
            }
        }
    }

    private func details(_ trip: TripRecovery.FoundTrip) -> String {
        var parts: [String] = []
        if let s = trip.start, let e = trip.end { parts.append("\(Fmt.day(s)) → \(Fmt.day(e))") }
        parts.append("\(trip.items) éléments")
        if trip.alreadyPresent { parts.append("déjà dans Mes voyages") }
        return parts.joined(separator: " · ")
    }
}
