import Foundation
import CoreData

/// Export / import .zip (JSON + pièces jointes), générique sur le modèle Core Data :
/// tout attribut ajouté dans une future version du modèle est exporté automatiquement.
enum ExportImportService {
    static let jsonName = "monvoyage.json"
    static let format = "monvoyage-export"

    struct Value: Codable, Equatable {
        /// "s" texte, "n" nombre, "b" booléen, "date", "uuid", "file"
        var t: String
        var s: String?
        var n: Double?
        var b: Bool?
    }

    struct Record: Codable {
        var ref: String
        var entity: String
        var attributes: [String: Value]
        var toOne: [String: String]
        var toMany: [String: [String]]
    }

    struct TripExport: Codable {
        var records: [Record]
    }

    struct Document: Codable {
        var format: String
        var version: Int
        var exportedAt: Date
        var trips: [TripExport]
    }

    enum ImportError: Error, LocalizedError {
        case notMonVoyage, missingJSON
        var errorDescription: String? {
            switch self {
            case .notMonVoyage: return "Ce fichier n'est pas un export MonVoyage."
            case .missingJSON: return "L'archive ne contient pas de fichier monvoyage.json."
            }
        }
    }

    // MARK: - Export

    /// Tous les objets reliés au voyage (parcours du graphe).
    static func collect(_ trip: Trip) -> [NSManagedObject] {
        var seen = Set<NSManagedObjectID>()
        var ordered: [NSManagedObject] = []
        var queue: [NSManagedObject] = [trip]
        while !queue.isEmpty {
            let object = queue.removeFirst()
            if seen.contains(object.objectID) { continue }
            seen.insert(object.objectID)
            ordered.append(object)
            for (name, relationship) in object.entity.relationshipsByName {
                if relationship.isToMany {
                    let set = object.value(forKey: name) as? NSSet
                    for case let related as NSManagedObject in set?.allObjects ?? [] where !seen.contains(related.objectID) {
                        queue.append(related)
                    }
                } else if let related = object.value(forKey: name) as? NSManagedObject, !seen.contains(related.objectID) {
                    queue.append(related)
                }
            }
        }
        return ordered
    }

    static func makeArchive(trips: [Trip]) throws -> Data {
        var files: [ZipEntry] = []
        var exports: [TripExport] = []
        for (tripIndex, trip) in trips.enumerated() {
            let objects = collect(trip)
            var refs: [NSManagedObjectID: String] = [:]
            for (i, object) in objects.enumerated() { refs[object.objectID] = "t\(tripIndex)-o\(i)" }
            var records: [Record] = []
            for object in objects {
                let ref = refs[object.objectID]!
                var attributes: [String: Value] = [:]
                for (name, attribute) in object.entity.attributesByName {
                    guard let raw = object.value(forKey: name) else { continue }
                    switch attribute.attributeType {
                    case .stringAttributeType:
                        if let s = raw as? String { attributes[name] = Value(t: "s", s: s) }
                    case .booleanAttributeType:
                        attributes[name] = Value(t: "b", b: (raw as? NSNumber)?.boolValue ?? false)
                    case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType,
                         .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
                        if let n = raw as? NSNumber { attributes[name] = Value(t: "n", n: n.doubleValue) }
                    case .dateAttributeType:
                        if let d = raw as? Date { attributes[name] = Value(t: "date", n: d.timeIntervalSinceReferenceDate) }
                    case .UUIDAttributeType:
                        if let u = raw as? UUID { attributes[name] = Value(t: "uuid", s: u.uuidString) }
                    case .binaryDataAttributeType:
                        if let data = raw as? Data {
                            let path = "files/\(ref)-\(name).bin"
                            files.append(ZipEntry(path: path, data: data))
                            attributes[name] = Value(t: "file", s: path)
                        }
                    default:
                        continue
                    }
                }
                var toOne: [String: String] = [:]
                var toMany: [String: [String]] = [:]
                for (name, relationship) in object.entity.relationshipsByName {
                    if relationship.isToMany {
                        let set = object.value(forKey: name) as? NSSet
                        let ids = (set?.allObjects as? [NSManagedObject] ?? []).compactMap { refs[$0.objectID] }
                        if !ids.isEmpty { toMany[name] = ids.sorted() }
                    } else if let related = object.value(forKey: name) as? NSManagedObject, let id = refs[related.objectID] {
                        toOne[name] = id
                    }
                }
                records.append(Record(ref: ref, entity: object.entity.name ?? "", attributes: attributes, toOne: toOne, toMany: toMany))
            }
            exports.append(TripExport(records: records))
        }
        let document = Document(format: format, version: 1, exportedAt: Date(), trips: exports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(document)
        return ZipArchive.write([ZipEntry(path: jsonName, data: json)] + files)
    }

    /// Écrit l'archive dans un fichier temporaire, prêt pour la feuille de partage.
    static func exportFile(trips: [Trip]) throws -> URL {
        let data = try makeArchive(trips: trips)
        let base: String
        if trips.count == 1, let name = trips.first?.name, !name.isEmpty {
            base = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        } else {
            base = "tous-les-voyages"
        }
        let day = DayKey.key(Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MonVoyage-\(base)-\(day).zip")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    /// Recrée les voyages à l'identique, avec de nouveaux UUID.
    @discardableResult
    static func importArchive(_ archive: Data, into context: NSManagedObjectContext, renameSuffix: String? = nil) throws -> [Trip] {
        let entries = try ZipArchive.read(archive)
        var files: [String: Data] = [:]
        for entry in entries { files[entry.path] = entry.data }
        guard let json = files[jsonName] else { throw ImportError.missingJSON }
        let document = try JSONDecoder().decode(Document.self, from: json)
        guard document.format == format else { throw ImportError.notMonVoyage }

        let store = PersistenceController.controller(for: context)?.privateStore
        var imported: [Trip] = []
        for tripExport in document.trips {
            var objects: [String: NSManagedObject] = [:]
            for record in tripExport.records {
                guard NSEntityDescription.entity(forEntityName: record.entity, in: context) != nil else { continue }
                let object = NSEntityDescription.insertNewObject(forEntityName: record.entity, into: context)
                if let store { context.assign(object, to: store) }
                for (name, value) in record.attributes {
                    guard let attribute = object.entity.attributesByName[name] else { continue }
                    object.setValue(decode(value, attribute: attribute, files: files), forKey: name)
                }
                if object.entity.attributesByName["id"] != nil { object.setValue(UUID(), forKey: "id") }
                objects[record.ref] = object
            }
            for record in tripExport.records {
                guard let object = objects[record.ref] else { continue }
                for (name, ref) in record.toOne where object.entity.relationshipsByName[name] != nil {
                    object.setValue(objects[ref], forKey: name)
                }
                for (name, refs) in record.toMany where object.entity.relationshipsByName[name] != nil {
                    object.setValue(NSSet(array: refs.compactMap { objects[$0] }), forKey: name)
                }
            }
            if let trip = objects.values.compactMap({ $0 as? Trip }).first {
                if let renameSuffix { trip.name = (trip.name ?? "") + renameSuffix }
                imported.append(trip)
            }
        }
        context.saveIfNeeded()
        return imported
    }

    private static func decode(_ value: Value, attribute: NSAttributeDescription, files: [String: Data]) -> Any? {
        switch value.t {
        case "s": return value.s
        case "b": return NSNumber(value: value.b ?? false)
        case "n":
            let n = value.n ?? 0
            switch attribute.attributeType {
            case .integer16AttributeType: return NSNumber(value: Int16(clamping: Int(n)))
            case .integer32AttributeType: return NSNumber(value: Int32(clamping: Int(n)))
            case .integer64AttributeType: return NSNumber(value: Int64(n))
            default: return NSNumber(value: n)
            }
        case "date": return value.n.map { Date(timeIntervalSinceReferenceDate: $0) }
        case "uuid": return value.s.flatMap { UUID(uuidString: $0) }
        case "file": return value.s.flatMap { files[$0] }
        default: return nil
        }
    }

    /// Duplique un voyage (même mécanique que l'export / import).
    @discardableResult
    static func duplicate(_ trip: Trip, in context: NSManagedObjectContext) throws -> Trip? {
        let archive = try makeArchive(trips: [trip])
        let trips = try importArchive(archive, into: context, renameSuffix: " (copie)")
        return trips.first
    }
}
