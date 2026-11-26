import Foundation
import CoreData

/// Journal des synchronisations iCloud de Core Data (envoi / réception), avec l'erreur exacte.
/// Sert au dépannage du partage : conservé sur l'iPhone (20 derniers événements).
final class SyncEventLog: @unchecked Sendable {
    static let shared = SyncEventLog()

    struct Entry: Codable {
        var date: Date
        var kind: String      // configuration, réception, envoi
        var store: String     // privé, partagé
        var succeeded: Bool
        var error: String?
    }

    private let key = "syncEventLog"
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    func start(_ controller: PersistenceController) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: controller.container, queue: nil
        ) { [weak self, weak controller] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let kind: String
            switch event.type {
            case .setup: kind = "configuration"
            case .import: kind = "réception"
            case .export: kind = "envoi"
            @unknown default: kind = "autre"
            }
            let store = event.storeIdentifier == controller?.sharedStore?.identifier ? "partagé" : "privé"
            if store == "partagé", let raw = event.error, SharedStoreReset.looksCorrupted(raw) {
                SharedStoreReset.request()
            }
            let error = event.error.map { String(CloudKitErrorReport.describe($0).prefix(4000)) }
            self?.append(Entry(date: event.endDate ?? Date(), kind: kind, store: store,
                               succeeded: event.succeeded, error: error))
        }
    }

    private func append(_ entry: Entry) {
        lock.lock(); defer { lock.unlock() }
        var list = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        list.append(entry)
        if list.count > 20 { list.removeFirst(list.count - 20) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Résumé lisible : dernier envoi réussi, dernières erreurs.
    func summary(limit: Int = 2) -> String {
        let list = entries
        guard !list.isEmpty else { return "Aucune synchronisation iCloud enregistrée depuis l'installation de cette version." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM HH:mm:ss"
        var lines: [String] = []
        if let ok = list.last(where: { $0.kind == "envoi" && $0.succeeded }) {
            lines.append("Dernier envoi réussi (\(ok.store)) : \(formatter.string(from: ok.date)).")
        } else {
            lines.append("Aucun envoi iCloud réussi enregistré.")
        }
        let failures = list.filter { !$0.succeeded }.suffix(limit)
        for f in failures {
            lines.append("❌ \(f.kind) (\(f.store)) \(formatter.string(from: f.date)) :\n\(f.error ?? "erreur inconnue")")
        }
        if failures.isEmpty { lines.append("Aucune erreur de synchronisation enregistrée.") }
        return lines.joined(separator: "\n")
    }
}
