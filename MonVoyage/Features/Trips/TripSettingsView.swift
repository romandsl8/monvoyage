import SwiftUI
import CoreData
import UIKit

/// Voyage et voyageurs : infos, partage, passeports / ESTA, rappels libres.
struct TripSettingsView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var nav: TripNavigation
    @EnvironmentObject private var router: AppRouter
    @State private var sharing = false
    @State private var copyingLink = false
    @State private var checking = false
    @State private var newReminderTitle = ""
    @State private var newReminderDate = Date().addingTimeInterval(86400)
    @State private var exportURL: URL?

    private var sharedWithMeText: String {
        if let owner = CloudSharing.ownerName(for: trip) { return "Partagé avec moi par \(owner)" }
        return "Partagé avec moi"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Destination", value: trip.city ?? "—")
                if let s = trip.startDate, let e = trip.endDate {
                    LabeledContent("Dates", value: "\(Fmt.day(s)) → \(Fmt.day(e))")
                }
                LabeledContent("Budget", value: Fmt.eur(trip.totalBudgetEUR))
                Button { nav.present(.editTrip) } label: { Label("Modifier le voyage", systemImage: "pencil") }
            }

            Section {
                if CloudSharing.isShared(trip) {
                    if CloudSharing.isParticipant(trip) {
                        Label(sharedWithMeText, systemImage: "person.2.fill")
                    } else {
                        let names = CloudSharing.participantNames(for: trip)
                        Label(names.isEmpty ? "Partagé (invitation en attente)" : "Partagé avec \(names.joined(separator: ", "))", systemImage: "person.2.fill")
                    }
                }
                Button {
                    Task {
                        sharing = true
                        defer { sharing = false }
                        do { try await CloudSharing.presentSharingController(for: trip) }
                        catch { router.alertMessage = "Partage impossible : \(error.localizedDescription). Vérifiez que vous êtes connecté à iCloud." }
                    }
                } label: {
                    HStack {
                        Label(CloudSharing.isShared(trip) ? "Gérer le partage" : "Partager ce voyage", systemImage: "person.crop.circle.badge.plus")
                        if sharing { Spacer(); ProgressView() }
                    }
                }
                .disabled(sharing || copyingLink)
                if !CloudSharing.isParticipant(trip) {
                    Button {
                        Task {
                            copyingLink = true
                            defer { copyingLink = false }
                            do {
                                let url = try await CloudSharing.invitationLink(for: trip)
                                UIPasteboard.general.url = url
                                router.alertMessage = "Lien d'invitation copié. Collez-le dans un message (SMS, WhatsApp, e-mail…) à la personne invitée : en le touchant, elle rejoindra le voyage dans MonVoyage."
                            } catch {
                                router.alertMessage = "Lien impossible à créer : \(error.localizedDescription). Vérifiez que vous êtes connecté à iCloud (Réglages › votre nom › iCloud) et à internet."
                            }
                        }
                    } label: {
                        HStack {
                            Label("Copier le lien d'invitation", systemImage: "link")
                            if copyingLink { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(sharing || copyingLink)
                }
                if CloudSharing.isShared(trip) {
                    Button {
                        Task {
                            checking = true
                            defer { checking = false }
                            let report = await CloudSharing.iCloudReport(for: trip)
                            UIPasteboard.general.string = report
                            router.alertMessage = report + "\n\n(Ce message est copié : vous pouvez le coller pour l'envoyer.)"
                        }
                    } label: {
                        HStack {
                            Label("Vérifier le partage sur iCloud", systemImage: "checkmark.icloud")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(sharing || copyingLink || checking)
                }
            } header: {
                Text("Partage à deux")
            } footer: {
                Text("Invitez l'autre voyageur par Messages, ou copiez le lien d'invitation pour l'envoyer par n'importe quelle messagerie. L'invité pourra modifier le voyage. Depuis « Gérer le partage », le propriétaire peut arrêter le partage.")
            }

            ForEach(trip.travelerList, id: \.objectID) { traveler in
                TravelerSection(traveler: traveler, trip: trip)
            }
            Section {
                Button {
                    let t = context.make(Traveler.self, trip: trip)
                    t.name = "Voyageur \(trip.travelerList.count + 1)"
                    t.sortIndex = Int32(trip.travelerList.count)
                    t.trip = trip
                    context.saveIfNeeded()
                } label: { Label("Ajouter un voyageur", systemImage: "person.badge.plus") }
            }

            Section("Rappels libres") {
                ForEach(trip.reminderList, id: \.objectID) { reminder in
                    VStack(alignment: .leading) {
                        Text(reminder.title ?? "Rappel")
                        if let date = reminder.date { Text(Fmt.dateTime(date)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(trip.reminderList[i]) }
                    context.saveIfNeeded()
                }
                TextField("Nouveau rappel", text: $newReminderTitle)
                DatePicker("Quand", selection: $newReminderDate)
                Button("Ajouter le rappel") {
                    let r = context.make(Reminder.self, trip: trip)
                    r.title = newReminderTitle
                    r.date = newReminderDate
                    r.notificationID = "rem-\(r.id?.uuidString ?? "")"
                    r.trip = trip
                    context.saveIfNeeded()
                    newReminderTitle = ""
                }
                .disabled(newReminderTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Sauvegarde") {
                Button { exportURL = try? ExportImportService.exportFile(trips: [trip]); AppSettings.shared.lastExportDate = Date() } label: {
                    Label("Exporter ce voyage (.zip)", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Voyage et voyageurs")
        .groupedBackground()
        .sheet(item: Binding(get: { exportURL.map(ShareableURL.init) }, set: { exportURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }
}

/// Un voyageur : nom, passeport, ESTA, avec alertes d'expiration.
struct TravelerSection: View {
    @ObservedObject var traveler: Traveler
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        Section {
            TextField("Nom", text: Binding(get: { traveler.name ?? "" }, set: { traveler.name = $0; context.saveIfNeeded() }))
            optionalDate("Expiration du passeport", value: Binding(get: { traveler.passportExpiry }, set: { traveler.passportExpiry = $0; context.saveIfNeeded() }))
            optionalDate("Expiration de l'ESTA", value: Binding(get: { traveler.estaExpiry }, set: { traveler.estaExpiry = $0; context.saveIfNeeded() }))
            TextField("N° de dossier ESTA", text: Binding(get: { traveler.estaNumber ?? "" }, set: { traveler.estaNumber = $0; context.saveIfNeeded() }))
                .textInputAutocapitalization(.characters)
            ForEach(DocumentAlerts.alerts(for: traveler, trip: trip), id: \.self) { alert in
                Label(alert, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote)
            }
        } header: {
            Text(traveler.wName)
        }
    }

    private func optionalDate(_ title: String, value: Binding<Date?>) -> some View {
        HStack {
            if let date = value.wrappedValue {
                DatePicker(title, selection: Binding(get: { date }, set: { value.wrappedValue = $0 }), displayedComponents: .date)
                Button { value.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer la date")
            } else {
                Text(title)
                Spacer()
                Button("Renseigner") { value.wrappedValue = trip.endDate ?? Date() }
            }
        }
    }
}

/// Alertes passeport / ESTA.
enum DocumentAlerts {
    static func alerts(for traveler: Traveler, trip: Trip) -> [String] {
        var result: [String] = []
        let end = trip.endDate ?? Date()
        if let p = traveler.passportExpiry, DayKey.key(p) < DayKey.key(end) {
            result.append("Le passeport expire avant la date de retour.")
        }
        if let e = traveler.estaExpiry, DayKey.key(e) < DayKey.key(end) {
            result.append("L'ESTA expire avant la date de retour.")
        }
        if (traveler.estaNumber ?? "").isEmpty, trip.isUpcoming() {
            result.append("ESTA non renseignée.")
        }
        return result
    }

    static func allAlerts(trip: Trip) -> [String] {
        trip.travelerList.flatMap { t in alerts(for: t, trip: trip).map { "\(t.wName) : \($0)" } }
    }
}
