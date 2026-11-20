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
        return try await withCheckedThrowingContinuation { continuation in
            controller.container.share([trip], to: nil) { _, share, _, error in
                if let share {
                    share[CKShare.SystemFieldKey.title] = trip.wName as CKRecordValue
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: error ?? CKError(.internalError))
                }
            }
        }
    }

    /// Présente la feuille de partage iCloud (invitation par Messages ou lien, lecture/écriture).
    static func presentSharingController(for trip: Trip) async throws {
        let share = try await share(trip)
        let container = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let sharingController = UICloudSharingController(share: share, container: container)
        sharingController.availablePermissions = [.allowReadWrite, .allowPrivate]
        let delegate = SharingDelegate(tripName: trip.wName, store: controller.store(for: trip))
        SharingDelegate.current = delegate
        sharingController.delegate = delegate
        sharingController.modalPresentationStyle = .formSheet
        guard let top = UIApplication.topViewController() else { return }
        top.present(sharingController, animated: true)
    }

    /// Accepte une invitation reçue dans le magasin partagé.
    static func accept(_ metadata: CKShare.Metadata) {
        guard let sharedStore = controller.sharedStore else { return }
        controller.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error { print("Acceptation du partage impossible : \(error)") }
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
