import Foundation
import CoreData
import CloudKit
import UIKit

/// Partage d'un voyage entre deux comptes iCloud (CKShare via NSPersistentCloudKitContainer).
@MainActor
enum CloudSharing {
    static var controller: PersistenceController { .shared }

    static func existingShare(for trip: Trip) -> CKShare? {
        guard let shares = try? controller.container.fetchShares(matching: [trip.objectID]) else { return nil }
        return shares[trip.objectID]
    }

    /// true si le voyage vient du magasin partagé (je suis participant).
    static func isParticipant(_ trip: Trip) -> Bool {
        controller.isShared(trip)
    }

    static func isShared(_ trip: Trip) -> Bool {
        isParticipant(trip) || existingShare(for: trip) != nil
    }

    /// Noms des participants (hors propriétaire courant).
    static func participantNames(for trip: Trip) -> [String] {
        guard let share = existingShare(for: trip) else { return [] }
        return share.participants.compactMap { participant in
            if participant == share.currentUserParticipant { return nil }
            if let components = participant.userIdentity.nameComponents {
                let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
                if !name.isEmpty { return name }
            }
            return participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.lookupInfo?.phoneNumber ?? "Invité"
        }
    }

    static func ownerName(for trip: Trip) -> String? {
        guard let share = existingShare(for: trip),
              let components = share.owner.userIdentity.nameComponents else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name.isEmpty ? nil : name
    }

    /// Crée (ou récupère) le partage du voyage. Chaque étape iCloud a un délai maximal :
    /// en cas de blocage, l'erreur indique l'étape concernée au lieu de charger sans fin.
    static func share(_ trip: Trip) async throws -> CKShare {
        if let existing = existingShare(for: trip) { return existing }
        // Le voyage doit être enregistré avant d'être partagé.
        trip.managedObjectContext?.saveIfNeeded()
        let share: CKShare = try await withTimeout(45, step: "création du partage iCloud") { done in
            controller.container.share([trip], to: nil) { _, share, _, error in
                if let share { done(.success(share)) } else { done(.failure(error ?? CKError(.internalError))) }
            }
        }
        // Titre affiché dans l'invitation, enregistré sur iCloud (facultatif).
        share[CKShare.SystemFieldKey.title] = trip.wName as CKRecordValue
        return (try? await persist(share, trip: trip)) ?? share
    }

    /// Enregistre une modification du partage sur iCloud.
    static func persist(_ share: CKShare, trip: Trip) async throws -> CKShare {
        guard let store = controller.store(for: trip) else { return share }
        return try await withTimeout(30, step: "enregistrement du partage sur iCloud") { done in
            controller.container.persistUpdatedShare(share, in: store) { saved, error in
                if let saved { done(.success(saved)) } else { done(.failure(error ?? CKError(.internalError))) }
            }
        }
    }

    /// Lien d'invitation ouvert à toute personne qui le reçoit (lecture et écriture),
    /// à envoyer par n'importe quelle messagerie.
    static func invitationLink(for trip: Trip) async throws -> URL {
        let share = try await share(trip)
        var current = share
        if share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            current = (try? await persist(share, trip: trip)) ?? share
        }
        if let url = current.url ?? share.url { return url }
        // Pas de lien : le partage n'a jamais atteint le serveur (ex. créé avant que le
        // schéma iCloud soit complet). On le récupère ou on l'enregistre directement sur iCloud.
        let repaired = try await repairOnServer(current, trip: trip)
        guard let url = repaired.url else { throw SharingError.noLink }
        return url
    }

    /// Récupère le partage sur iCloud, ou l'y enregistre (zone comprise) s'il est absent.
    static func repairOnServer(_ share: CKShare, trip: Trip) async throws -> CKShare {
        let database = CKContainer(identifier: PersistenceController.cloudKitContainerID).privateCloudDatabase
        let zoneID = share.recordID.zoneID
        var serverShare: CKShare?
        do {
            serverShare = try await database.record(for: share.recordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            serverShare = nil
        } catch {
            throw SharingError.cloud("lecture du partage", error)
        }
        if serverShare == nil {
            do {
                _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            } catch {
                throw SharingError.cloud("création de la zone de partage", error)
            }
            share.publicPermission = .readWrite
            share[CKShare.SystemFieldKey.title] = trip.wName as CKRecordValue
            do {
                let result = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .allKeys)
                if case .success(let record)? = result.saveResults[share.recordID] {
                    serverShare = record as? CKShare
                } else if case .failure(let error)? = result.saveResults[share.recordID] {
                    throw error
                }
            } catch let error as SharingError {
                throw error
            } catch {
                throw SharingError.cloud("enregistrement du partage", error)
            }
        } else if let existing = serverShare, existing.publicPermission != .readWrite {
            existing.publicPermission = .readWrite
            if let result = try? await database.modifyRecords(saving: [existing], deleting: [], savePolicy: .changedKeys),
               case .success(let record)? = result.saveResults[existing.recordID] {
                serverShare = record as? CKShare
            }
        }
        guard let fixed = serverShare else { throw SharingError.noLink }
        // Met à jour la copie locale du partage et relance la synchronisation du voyage.
        if let store = controller.store(for: trip) {
            controller.container.persistUpdatedShare(fixed, in: store) { _, _ in }
        }
        resendTripData(trip)
        return fixed
    }

    enum SharingError: LocalizedError {
        case timeout(String)
        case noLink
        case cloud(String, Error)
        var errorDescription: String? {
            switch self {
            case .timeout(let step): return "iCloud ne répond pas (étape : \(step))"
            case .noLink: return "iCloud n'a pas fourni de lien d'invitation"
            case .cloud(let step, let error):
                let code = (error as? CKError).map { " [code \($0.errorCode)]" } ?? ""
                return "erreur iCloud (\(step))\(code) : \(error.localizedDescription)"
            }
        }
    }

    /// Attend un rappel iCloud au plus `seconds` secondes.
    private static func withTimeout<T>(_ seconds: Double, step: String,
                                       _ body: (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                if once.claim() { continuation.resume(throwing: SharingError.timeout(step)) }
            }
            body { result in
                if once.claim() { continuation.resume(with: result) }
            }
        }
    }

    /// Invitation : feuille de partage iOS (Messages, Mail, Copier le lien…) avec le partage iCloud
    /// en lecture et écriture. Si quelqu'un a déjà rejoint, ouvre la gestion du partage
    /// (participants, arrêter / quitter le partage).
    static func presentSharingController(for trip: Trip) async throws {
        let hadShare = existingShare(for: trip) != nil
        var share = try await share(trip)
        if share.url == nil && !isParticipant(trip) {
            share = try await repairOnServer(share, trip: trip)
        }
        let container = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        guard let top = UIApplication.topViewController() else { return }

        let others = share.participants.filter { $0.role != .owner }
        if isParticipant(trip) || (hadShare && !others.isEmpty) {
            let sharingController = UICloudSharingController(share: share, container: container)
            sharingController.availablePermissions = [.allowReadWrite, .allowPrivate]
            let delegate = SharingDelegate(tripName: trip.wName, store: controller.store(for: trip))
            SharingDelegate.current = delegate
            sharingController.delegate = delegate
            sharingController.modalPresentationStyle = .formSheet
            top.present(sharingController, animated: true)
            return
        }

        let provider = NSItemProvider()
        let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite,
                                              allowedParticipantAccessOptions: .any)
        provider.registerCKShare(share, container: container, allowedSharingOptions: options)
        let activity = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [provider]))
        if let popover = activity.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(activity, animated: true)
    }


    // MARK: - Contrôle et réparation du contenu partagé

    /// Marque tous les éléments du voyage comme modifiés pour qu'iCloud les reçoive à nouveau
    /// (utile si un premier envoi a échoué, par exemple avant que le schéma soit complet).
    /// Ne supprime ni ne change aucune donnée.
    @discardableResult
    static func resendTripData(_ trip: Trip) -> Int {
        guard let context = trip.managedObjectContext else { return 0 }
        let store = trip.objectID.persistentStore
        var seen = Set<NSManagedObjectID>()
        var queue: [NSManagedObject] = [trip]
        let now = Date()
        while let object = queue.popLast() {
            guard !object.isDeleted, object.objectID.persistentStore == store,
                  seen.insert(object.objectID).inserted else { continue }
            if object.entity.attributesByName["updatedAt"] != nil { object.setValue(now, forKey: "updatedAt") }
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
        context.saveIfNeeded()
        return seen.count
    }

    private static func codeText(_ error: Error) -> String {
        (error as? CKError).map { " [code \($0.errorCode)]" } ?? ""
    }

    private static func displayName(_ participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.lookupInfo?.phoneNumber ?? "Invité"
    }

    /// Nombre d'enregistrements par type dans une zone iCloud.
    private static func zoneCounts(_ database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        var token: CKServerChangeToken?
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token,
                                                               desiredKeys: ["CD_entityName"], resultsLimit: nil)
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result {
                    counts[modification.record.recordType, default: 0] += 1
                }
            }
            token = changes.changeToken
            more = changes.moreComing
        }
        return counts
    }

    private static func describe(_ counts: [String: Int]) -> String {
        let trips = counts["CD_Trip"] ?? 0
        let items = counts.filter { $0.key.hasPrefix("CD_") }.values.reduce(0, +)
        return "\(trips) voyage\(trips > 1 ? "s" : ""), \(items) élément\(items > 1 ? "s" : "") au total"
    }

    /// Ce qu'iCloud contient réellement pour ce voyage partagé (propriétaire ou invité).
    /// Côté propriétaire, si le voyage n'est pas sur iCloud, ses données sont renvoyées.
    static func iCloudReport(for trip: Trip) async -> String {
        guard let share = existingShare(for: trip) else { return "Ce voyage n'est pas encore partagé." }
        let participant = isParticipant(trip)
        let ck = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let database = participant ? ck.sharedCloudDatabase : ck.privateCloudDatabase
        var lines: [String] = []
        do {
            if let server = try await database.record(for: share.recordID) as? CKShare {
                let access: String
                switch server.publicPermission {
                case .readWrite: access = "toute personne ayant le lien (modification)"
                case .readOnly: access = "toute personne ayant le lien (lecture)"
                default: access = "sur invitation uniquement"
                }
                lines.append("Partage sur iCloud : présent, lien \(server.url == nil ? "absent" : "actif"), accès \(access).")
                let others = server.participants.filter { $0.role != .owner }
                if others.isEmpty { lines.append("Personne n'a encore rejoint le voyage.") }
                for p in others {
                    let status: String
                    switch p.acceptanceStatus {
                    case .accepted: status = "a rejoint"
                    case .pending: status = "invitation en attente"
                    case .removed: status = "retiré"
                    default: status = "état inconnu"
                    }
                    lines.append("• \(displayName(p)) : \(status)")
                }
            } else {
                lines.append("Partage introuvable sur iCloud.")
            }
        } catch {
            lines.append("Partage illisible sur iCloud\(codeText(error)) : \(error.localizedDescription)")
        }
        do {
            let counts = try await zoneCounts(database, zoneID: share.recordID.zoneID)
            lines.append("Contenu partagé sur iCloud : \(describe(counts)).")
            if !participant && (counts["CD_Trip"] ?? 0) == 0 {
                let n = resendTripData(trip)
                lines.append("Le voyage manquait sur iCloud : \(n) éléments viennent d'être renvoyés. Laissez l'appli ouverte une minute puis vérifiez à nouveau.")
            }
        } catch {
            lines.append("Contenu illisible sur iCloud\(codeText(error)) : \(error.localizedDescription)")
            if !participant {
                let n = resendTripData(trip)
                lines.append("\(n) éléments du voyage viennent d'être renvoyés. Vérifiez à nouveau dans une minute.")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Côté invité : voyages partagés avec moi, sur l'iPhone et sur iCloud.
    static func sharedWithMeReport() async -> String {
        var lines: [String] = []
        let ck = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        if let status = try? await ck.accountStatus(), status != .available {
            lines.append("⚠️ Compte iCloud indisponible sur cet iPhone (Réglages › votre nom › iCloud).")
        }
        guard let sharedStore = controller.sharedStore else {
            return (lines + ["Le stockage des voyages partagés n'a pas pu être chargé. Redémarrez l'appli."]).joined(separator: "\n")
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.affectedStores = [sharedStore]
        let local = (try? controller.viewContext.count(for: request)) ?? 0
        lines.append("Sur cet iPhone : \(local) voyage\(local > 1 ? "s" : "") partagé\(local > 1 ? "s" : "") avec moi.")
        do {
            let zones = try await ck.sharedCloudDatabase.allRecordZones()
            if zones.isEmpty {
                lines.append("Sur iCloud : aucun voyage partagé n'a été rejoint avec ce compte. Collez le lien d'invitation ci-dessous pour le rejoindre.")
            }
            for zone in zones {
                do {
                    let counts = try await zoneCounts(ck.sharedCloudDatabase, zoneID: zone.zoneID)
                    lines.append("Sur iCloud, voyage partagé avec moi : \(describe(counts)).")
                } catch {
                    lines.append("Partage illisible sur iCloud\(codeText(error)) : \(error.localizedDescription)")
                }
            }
        } catch {
            lines.append("Lecture iCloud impossible\(codeText(error)) : \(error.localizedDescription)")
        }
        return lines.joined(separator: "\n")
    }

    /// Rejoint un voyage à partir du lien d'invitation collé (si toucher le lien n'a rien fait).
    static func join(link: URL) async throws -> String {
        let ck = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let metadata: CKShare.Metadata = try await withTimeout(30, step: "lecture de l'invitation") { done in
            let operation = CKFetchShareMetadataOperation(shareURLs: [link])
            let box = MetadataBox()
            operation.perShareMetadataResultBlock = { _, result in box.result = result }
            operation.fetchShareMetadataResultBlock = { result in
                if case .failure(let error) = result { done(.failure(error)); return }
                done(box.result ?? .failure(SharingError.noLink))
            }
            ck.add(operation)
        }
        let title = (metadata.share[CKShare.SystemFieldKey.title] as? String) ?? "partagé"
        if metadata.participantRole == .owner {
            return "Ce lien est celui de votre propre voyage « \(title) » : il doit être ouvert par la personne invitée, sur son iPhone."
        }
        guard let sharedStore = controller.sharedStore else {
            throw SharingError.cloud("stockage des voyages partagés non chargé", CKError(.internalError))
        }
        let _: Bool = try await withTimeout(60, step: "acceptation de l'invitation") { done in
            controller.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                if let error { done(.failure(error)) } else { done(.success(true)) }
            }
        }
        return "Vous avez rejoint le voyage « \(title) ». Il apparaîtra dans Mes voyages d'ici une minute, le temps de la synchronisation iCloud."
    }

    /// Accepte une invitation reçue dans le magasin partagé.
    static func accept(_ metadata: CKShare.Metadata) {
        guard let sharedStore = controller.sharedStore else {
            AppRouter.shared.alertMessage = "Impossible de rejoindre le voyage partagé : le stockage des voyages partagés n'a pas pu être chargé. Redémarrez l'appli puis touchez à nouveau le lien."
            return
        }
        controller.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            let title = metadata.share[CKShare.SystemFieldKey.title] as? String
            Task { @MainActor in
                if let error {
                    AppRouter.shared.alertMessage = "Impossible de rejoindre le voyage partagé : \(error.localizedDescription). Vérifiez que vous êtes connecté à iCloud."
                } else {
                    AppRouter.shared.alertMessage = "Vous avez rejoint le voyage « \(title ?? "partagé") ». Il apparaîtra dans Mes voyages d'ici quelques instants, le temps de la synchronisation iCloud."
                }
            }
        }
    }
}

final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    static var current: SharingDelegate?
    let tripName: String
    let store: NSPersistentStore?

    init(tripName: String, store: NSPersistentStore?) {
        self.tripName = tripName
        self.store = store
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Erreur de partage : \(error)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { tripName }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share, let store {
            PersistenceController.shared.container.persistUpdatedShare(share, in: store) { _, error in
                if let error { print("Mise à jour du partage impossible : \(error)") }
            }
        }
    }

    /// « Arrêter le partage » (propriétaire) ou « Quitter » (participant) : géré par iCloud.
    /// Les données ne sont jamais purgées par le code (règle de conservation).
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        NotificationCenter.default.post(name: .monVoyageDataDidChange, object: nil)
    }
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Garantit qu'une continuation n'est reprise qu'une seule fois (réponse iCloud ou délai dépassé).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Résultat de lecture d'une invitation (rempli par CloudKit avant le rappel final).
private final class MetadataBox: @unchecked Sendable {
    var result: Result<CKShare.Metadata, Error>?
}
