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

    /// Crée (ou récupère) le partage du voyage.
    static func share(_ trip: Trip) async throws -> CKShare {
        if let existing = existingShare(for: trip) { return existing }
        // Le voyage doit être enregistré avant d'être partagé.
        trip.managedObjectContext?.saveIfNeeded()
        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            controller.container.share([trip], to: nil) { _, share, _, error in
                if let share {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: error ?? CKError(.internalError))
                }
            }
        }
        // Titre affiché dans l'invitation, enregistré sur iCloud.
        share[CKShare.SystemFieldKey.title] = trip.wName as CKRecordValue
        guard let store = controller.store(for: trip) else { return share }
        let updated: CKShare? = await withCheckedContinuation { continuation in
            controller.container.persistUpdatedShare(share, in: store) { saved, _ in
                continuation.resume(returning: saved)
            }
        }
        return updated ?? share
    }

    /// Invitation : feuille de partage iOS (Messages, Mail, Copier le lien…) avec le partage iCloud
    /// en lecture et écriture. Si quelqu'un a déjà rejoint, ouvre la gestion du partage
    /// (participants, arrêter / quitter le partage).
    static func presentSharingController(for trip: Trip) async throws {
        let hadShare = existingShare(for: trip) != nil
        let share = try await share(trip)
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

    /// Accepte une invitation reçue dans le magasin partagé.
    static func accept(_ metadata: CKShare.Metadata) {
        guard let sharedStore = controller.sharedStore else { return }
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
