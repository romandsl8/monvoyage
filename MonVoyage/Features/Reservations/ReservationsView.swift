import SwiftUI
import CoreData
import QuickLook

/// Réservations et documents (consultables hors ligne).
struct ReservationsView: View {
    @ObservedObject var trip: Trip
    @EnvironmentObject private var nav: TripNavigation
    @Environment(\.managedObjectContext) private var context
    @State private var expenseToDelete: Expense?
    @State private var refreshTick = 0

    /// Dépenses de type vol / hôtel / billets saisies dans Budget, sans fiche réservation.
    private var expensesWithoutReservation: [(expense: Expense, kind: ReservationKind)] {
        trip.expenseList.compactMap { expense in
            guard expense.reservation == nil, !ReservationLink.isDismissed(expense),
                  let kind = ReservationLink.kind(for: expense) else { return nil }
            return (expense: expense, kind: kind)
        }
    }

    var body: some View {
        List {
            let pending = expensesWithoutReservation
            if !pending.isEmpty {
                Section {
                    ForEach(pending, id: \.expense.objectID) { item in
                        Button {
                            let reservation = ReservationLink.createReservation(for: item.expense, kind: item.kind, trip: trip, context: context)
                            nav.present(.editReservation(reservation.objectID))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.kind.symbol).foregroundStyle(Color.accentColor).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.expense.wTitle).foregroundStyle(.primary)
                                    Text("\(item.kind.label) · \(Fmt.money(item.expense.amount, item.expense.currencyCode))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Compléter").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { expenseToDelete = item.expense } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                            Button {
                                ReservationLink.dismissedKeys.insert(ReservationLink.key(for: item.expense))
                                refreshTick += 1
                            } label: {
                                Label("Ignorer", systemImage: "eye.slash")
                            }
                            .tint(.gray)
                        }
                    }
                } header: {
                    Text("À compléter")
                } footer: {
                    Text("Dépenses saisies dans le budget. Touchez-en une pour créer sa fiche (n° de confirmation, horaires de vol, documents) ; le budget et l'échéancier restent liés. Balayez vers la gauche pour la supprimer ou l'ignorer.")
                }
                .id(refreshTick)
            }
            if trip.reservationList.isEmpty && pending.isEmpty {
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
        .scrollContentBackground(.hidden)
        .groupedBackground()
        .confirmationDialog("Supprimer cette dépense ?",
                            isPresented: Binding(get: { expenseToDelete != nil }, set: { if !$0 { expenseToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer la dépense", role: .destructive) {
                if let expense = expenseToDelete {
                    context.delete(expense)
                    context.saveIfNeeded()
                }
                expenseToDelete = nil
            }
        } message: {
            Text("Elle sera retirée du budget et des échéances, avec ses versements.")
        }
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
            IconBubble(symbol: reservation.kind.symbol, tint: .accentColor, size: 38)
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
        .scrollContentBackground(.hidden)
        .groupedBackground()
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

/// Lien entre une dépense du budget et une fiche réservation.
enum ReservationLink {
    /// Type de réservation déduit de la catégorie (ou du libellé) de la dépense.
    static func kind(for expense: Expense) -> ReservationKind? {
        let category = (expense.category?.name ?? "").lowercased()
        let title = expense.wTitle.lowercased()
        // La catégorie prime (« Volcano Bay » en Billets parcs n'est pas un vol).
        if category == "vols" { return .flight }
        if category.contains("héberg") { return .hotel }
        if category.contains("billet") || category.contains("express") { return .parkTicket }
        if !category.isEmpty && !["divers", "transport"].contains(category) { return nil }
        let words = Set(title.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if words.contains("vol") || words.contains("vols") || words.contains("avion") || words.contains("flight") { return .flight }
        if words.contains("hôtel") || words.contains("hotel") || words.contains("airbnb") { return .hotel }
        if words.contains("location") || words.contains("voiture") { return .rental }
        if words.contains("assurance") { return .insurance }
        if words.contains("esta") { return .esta }
        return nil
    }

    /// Supprime une réservation et, sauf demande contraire, la dépense liée (et ses versements).
    /// Si la dépense est gardée, elle est marquée comme « sans fiche voulue » pour ne plus
    /// réapparaître dans « À compléter ».
    static func delete(_ reservation: Reservation, keepExpense: Bool, context: NSManagedObjectContext) {
        if let expense = reservation.expense {
            if keepExpense {
                expense.reservation = nil
                dismissedKeys.insert(key(for: expense))
            } else {
                context.delete(expense)
            }
        }
        context.delete(reservation)
        context.saveIfNeeded()
    }

    /// Dépenses volontairement gardées sans fiche (stocké sur l'iPhone).
    private static let dismissedDefaultsKey = "reservationLinkDismissed"
    static var dismissedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: dismissedDefaultsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: dismissedDefaultsKey) }
    }

    static func key(for expense: Expense) -> String {
        expense.id?.uuidString ?? expense.objectID.uriRepresentation().absoluteString
    }

    static func isDismissed(_ expense: Expense) -> Bool {
        dismissedKeys.contains(key(for: expense))
    }

    /// Crée la fiche réservation d'une dépense existante (montant, devise, date, lien conservés).
    @discardableResult
    static func createReservation(for expense: Expense, kind: ReservationKind, trip: Trip, context: NSManagedObjectContext) -> Reservation {
        let reservation = context.make(Reservation.self, trip: trip)
        reservation.trip = trip
        reservation.kindRaw = kind.rawValue
        reservation.title = expense.wTitle
        reservation.amount = expense.amount
        reservation.currency = expense.currencyCode
        reservation.startDate = expense.date
        reservation.provider = expense.merchant
        expense.reservation = reservation
        context.saveIfNeeded()
        return reservation
    }
}
