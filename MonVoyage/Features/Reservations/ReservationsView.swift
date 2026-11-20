import SwiftUI
import CoreData
import QuickLook

/// Réservations et documents (consultables hors ligne).
struct ReservationsView: View {
    @ObservedObject var trip: Trip
    @EnvironmentObject private var nav: TripNavigation

    var body: some View {
        List {
            if trip.reservationList.isEmpty {
                EmptyState(symbol: "doc.text", title: "Aucune réservation",
                           message: "Vols, hôtel, billets, assurance, ESTA… gardez tout au même endroit, même hors ligne.",
                           actionTitle: "Ajouter un vol") { nav.present(.newReservation(.flight)) }
                    .listRowBackground(Color.clear)
            }
            ForEach(ReservationKind.allCases) { kind in
                let items = trip.reservationList.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.label) {
                        ForEach(items, id: \.objectID) { reservation in
                            NavigationLink {
                                ReservationDetailView(reservation: reservation, trip: trip)
                            } label: {
                                ReservationRow(reservation: reservation)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Réservations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(ReservationKind.allCases) { kind in
                        Button { nav.present(.newReservation(kind)) } label: { Label(kind.label, systemImage: kind.symbol) }
                    }
                } label: { Label("Ajouter", systemImage: "plus") }
            }
        }
    }
}

struct ReservationRow: View {
    @ObservedObject var reservation: Reservation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reservation.kind.symbol).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.wTitle)
                if let first = reservation.segmentList.first, let dep = first.departureDate {
                    Text("\(first.routeText) · \(Fmt.dateTime(dep, timeZone: first.departureZone))").font(.caption).foregroundStyle(.secondary)
                } else if let start = reservation.startDate {
                    Text(Fmt.day(start)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !reservation.attachmentList.isEmpty {
                Image(systemName: "paperclip").foregroundStyle(.secondary).accessibilityLabel("Pièces jointes")
            }
        }
    }
}

/// Fiche détaillée (n° copiable, pièces jointes QuickLook, vols, dépense).
struct ReservationDetailView: View {
    @ObservedObject var reservation: Reservation
    @ObservedObject var trip: Trip
    @EnvironmentObject private var nav: TripNavigation
    @Environment(\.openURL) private var openURL
    @State private var previewURL: URL?
    @State private var copied = 0

    var body: some View {
        List {
            Section {
                if let number = reservation.confirmationNumber, !number.isEmpty {
                    copyRow("N° de confirmation", number)
                }
                if let pnr = reservation.pnr, !pnr.isEmpty { copyRow("Référence de dossier (PNR)", pnr) }
                if let provider = reservation.provider, !provider.isEmpty { LabeledContent("Prestataire", value: provider) }
                if let passengers = reservation.passengers, !passengers.isEmpty { LabeledContent("Passagers", value: passengers) }
                if let start = reservation.startDate { LabeledContent("Début", value: Fmt.dateShort(start)) }
                if let end = reservation.endDate { LabeledContent("Fin", value: Fmt.dateShort(end)) }
                if reservation.amount > 0 { LabeledContent("Montant", value: Fmt.money(reservation.amount, reservation.currencyCode)) }
                if let note = reservation.note, !note.isEmpty { Text(note) }
            }

            if !reservation.segmentList.isEmpty {
                Section("Trajets") {
                    ForEach(reservation.segmentList, id: \.objectID) { segment in
                        FlightSegmentCard(segment: segment) { url in openURL(url) }
                    }
                }
            }

            if !reservation.attachmentList.isEmpty {
                Section("Documents") {
                    ForEach(reservation.attachmentList, id: \.objectID) { attachment in
                        Button { previewURL = AttachmentFiles.temporaryURL(for: attachment) } label: {
                            Label(attachment.name ?? "Document", systemImage: attachment.mimeKind == "pdf" ? "doc.richtext" : "photo")
                        }
                    }
                }
            }

            Section {
                if reservation.amount > 0 && reservation.expense == nil {
                    Button {
                        nav.present(.newExpense(ExpensePrefill(title: reservation.wTitle, amount: reservation.amount,
                                                               currency: reservation.currencyCode,
                                                               categoryName: ReservationEditorView.categoryName(for: reservation.kind),
                                                               date: reservation.startDate ?? Date(), reservationID: reservation.objectID)))
                    } label: { Label("Créer la dépense correspondante", systemImage: "eurosign.circle") }
                } else if let expense = reservation.expense {
                    Button { nav.present(.editExpense(expense.objectID)) } label: { Label("Voir la dépense liée", systemImage: "eurosign.circle") }
                }
                Button { nav.present(.editReservation(reservation.objectID)) } label: { Label("Modifier", systemImage: "pencil") }
            }
        }
        .navigationTitle(reservation.wTitle)
        .quickLookPreview($previewURL)
        .sensoryFeedback(.success, trigger: copied)
    }

    private func copyRow(_ title: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied += 1
        } label: {
            LabeledContent(title) {
                HStack {
                    Text(value).font(.body.monospaced()).foregroundStyle(.primary)
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint("Appuyez pour copier")
    }
}

struct FlightSegmentCard: View {
    @ObservedObject var segment: FlightSegment
    let openStatus: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(segment.flightNumber ?? "") · \(segment.displayAirline)").font(.headline)
                Spacer()
                if let url = segment.statusURL {
                    Button("Statut") { openStatus(url) }.buttonStyle(.glass).font(.caption)
                }
            }
            HStack(alignment: .top) {
                endpoint(segment.departureIATA, segment.departureDate, segment.departureZone, label: "Départ")
                Spacer()
                VStack {
                    Image(systemName: "airplane").foregroundStyle(Color.accentColor)
                    Text(segment.durationText ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                endpoint(segment.arrivalIATA, segment.arrivalDate, segment.arrivalZone, label: "Arrivée")
            }
            let details = [segment.terminal.map { "Terminal \($0)" }, segment.seat.map { "Siège \($0)" },
                           segment.cabinClass, segment.baggage.map { "Bagages : \($0)" }]
                .compactMap { $0 }.filter { !$0.isEmpty && $0 != "Terminal " && $0 != "Siège " }
            if !details.isEmpty {
                Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func endpoint(_ code: String?, _ date: Date?, _ zone: TimeZone, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code ?? "???").font(.title2.bold()).fontDesign(.rounded)
            if let date {
                Text(Fmt.time(date, timeZone: zone)).font(.headline.monospacedDigit())
                Text(Fmt.day(date, timeZone: zone)).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(label) · heure locale").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fichiers temporaires pour QuickLook (les données restent dans Core Data, disponibles hors ligne).
enum AttachmentFiles {
    static func temporaryURL(for attachment: Attachment) -> URL? {
        temporaryURL(data: attachment.data, name: attachment.name, kind: attachment.mimeKind)
    }

    static func temporaryURL(data: Data?, name: String?, kind: String?) -> URL? {
        guard let data else { return nil }
        let ext = kind == "pdf" ? "pdf" : "jpg"
        let base = (name ?? "document").replacingOccurrences(of: "/", with: "-")
        let fileName = base.lowercased().hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apercus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        try? data.write(to: url, options: .atomic)
        return url
    }
}
