import SwiftUI
import CoreData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct FlightDraft: Identifiable, Equatable {
    var id = UUID()
    var objectID: NSManagedObjectID?
    var flightNumber = ""
    var airlineCode = ""
    var airlineName = ""
    var departureIATA = ""
    var arrivalIATA = ""
    var departureDate = Date()
    var arrivalDate = Date().addingTimeInterval(9 * 3600)
    var departureTZ = TimeZone.current.identifier
    var arrivalTZ = TimeZone.current.identifier
    var terminal = ""
    var seat = ""
    var cabinClass = ""
    var baggage = ""

    var departureZone: TimeZone { TimeZone(identifier: departureTZ) ?? .current }
    var arrivalZone: TimeZone { TimeZone(identifier: arrivalTZ) ?? .current }
}

struct AttachmentDraft: Identifiable, Equatable {
    var id = UUID()
    var objectID: NSManagedObjectID?
    var data: Data
    var kind: String
    var name: String
}

/// Création / modification d'une réservation (fiche vol détaillée incluse).
struct ReservationEditorView: View {
    @ObservedObject var trip: Trip
    let reservationID: NSManagedObjectID?
    let kind: ReservationKind

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reservationKind: ReservationKind = .other
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var hasDates = true
    @State private var confirmation = ""
    @State private var provider = ""
    @State private var amountText = ""
    @State private var currency = "EUR"
    @State private var note = ""
    @State private var pnr = ""
    @State private var passengers = ""
    @State private var flights: [FlightDraft] = []
    @State private var attachments: [AttachmentDraft] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var previewURL: URL?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var countInBudget = true
    @State private var hadExpense = false
    @State private var payment = PaymentDraft()
    @EnvironmentObject private var rates: ExchangeRateService

    private var amount: Double { Money.parse(amountText) ?? 0 }

    /// Date de la dépense liée : début de la réservation (premier vol), sinon aujourd'hui.
    private var paymentDate: Date {
        if reservationKind == .flight, let first = flights.map(\.departureDate).min() { return first }
        return hasDates ? start : Date()
    }

    static func categoryName(for kind: ReservationKind) -> String? {
        switch kind {
        case .flight: return "Vols"
        case .hotel: return "Hébergement"
        case .parkTicket: return "Billets parcs"
        case .rental: return "Transport"
        case .restaurant: return "Repas"
        default: return "Divers"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $reservationKind) {
                        ForEach(ReservationKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Titre", text: $title)
                    TextField("Prestataire", text: $provider)
                    TextField("N° de confirmation", text: $confirmation).textInputAutocapitalization(.characters)
                    if reservationKind != .flight {
                        Toggle("Dates", isOn: $hasDates)
                        if hasDates {
                            DatePicker("Début", selection: $start)
                            DatePicker("Fin", selection: $end, in: start...)
                        }
                    }
                }

                if reservationKind == .flight {
                    Section("Dossier") {
                        TextField("Référence de dossier (PNR)", text: $pnr).textInputAutocapitalization(.characters)
                        TextField("Passagers", text: $passengers)
                    }
                    ForEach($flights) { $flight in
                        FlightDraftSection(draft: $flight, index: flights.firstIndex(where: { $0.id == flight.id }) ?? 0) {
                            flights.removeAll { $0.id == flight.id }
                        }
                    }
                    Section {
                        Button {
                            var next = FlightDraft()
                            if let last = flights.last {
                                next.departureIATA = last.arrivalIATA
                                next.departureTZ = last.arrivalTZ
                                next.arrivalTZ = last.departureTZ
                                next.departureDate = last.arrivalDate.addingTimeInterval(2 * 3600)
                                next.arrivalDate = next.departureDate.addingTimeInterval(3 * 3600)
                            }
                            flights.append(next)
                        } label: { Label(flights.isEmpty ? "Ajouter un trajet" : "Ajouter un trajet (retour, escale…)", systemImage: "airplane.departure") }
                    }
                }

                Section {
                    AmountField(title: "Montant", text: $amountText, currency: currency)
                    Picker("Devise", selection: $currency) {
                        Text("€").tag("EUR")
                        Text("$").tag("USD")
                    }
                    .pickerStyle(.segmented)
                    if amount > 0 {
                        Toggle("Compter dans le budget", isOn: $countInBudget.animation())
                    }
                    TextField("Note", text: $note, axis: .vertical)
                } header: {
                    Text("Montant")
                } footer: {
                    if amount > 0 && countInBudget {
                        Text("La dépense correspondante est créée et mise à jour automatiquement avec cette réservation.")
                    }
                }

                if amount > 0 && countInBudget {
                    PaymentSections(draft: $payment, amount: amount, currency: currency,
                                    date: paymentDate, trip: trip)
                }

                Section("Pièces jointes") {
                    ForEach(attachments) { attachment in
                        Button { previewURL = AttachmentFiles.temporaryURL(data: attachment.data, name: attachment.name, kind: attachment.kind) } label: {
                            Label(attachment.name, systemImage: attachment.kind == "pdf" ? "doc.richtext" : "photo")
                        }
                    }
                    .onDelete { attachments.remove(atOffsets: $0) }
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Ajouter une photo", systemImage: "photo.badge.plus")
                    }
                    Button { showFileImporter = true } label: { Label("Ajouter un PDF", systemImage: "doc.badge.plus") }
                }

                if reservationID != nil {
                    Section { Button("Supprimer la réservation", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(reservationID == nil ? "Nouvelle réservation" : "Réservation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save) }
            }
            .onAppear(perform: load)
            .onChange(of: photoItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            attachments.append(AttachmentDraft(data: ImageCompression.jpeg(data), kind: "image",
                                                               name: "Photo \(attachments.count + 1)"))
                        }
                    }
                    photoItems = []
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    if let data = try? Data(contentsOf: url) {
                        attachments.append(AttachmentDraft(data: data, kind: "pdf", name: url.deletingPathExtension().lastPathComponent))
                    }
                    if access { url.stopAccessingSecurityScopedResource() }
                }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog("Supprimer cette réservation ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer la réservation et sa dépense", role: .destructive) {
                    if let reservationID, let r = try? context.existingObject(with: reservationID) as? Reservation {
                        ReservationLink.delete(r, keepExpense: false, context: context)
                    }
                    dismiss()
                }
                Button("Supprimer seulement la fiche") {
                    if let reservationID, let r = try? context.existingObject(with: reservationID) as? Reservation {
                        ReservationLink.delete(r, keepExpense: true, context: context)
                    }
                    dismiss()
                }
            } message: {
                Text("La dépense liée et son échéancier seront retirés du budget, sauf si vous ne supprimez que la fiche.")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        reservationKind = kind
        start = trip.startDate ?? Date()
        end = trip.endDate ?? Date()
        guard let reservationID, let r = try? context.existingObject(with: reservationID) as? Reservation else {
            if kind == .flight { flights = [defaultFlight()] }
            payment.categoryID = Self.categoryName(for: kind).flatMap { trip.category(named: $0)?.objectID }
            payment.isSettled = false
            return
        }
        if let expense = r.expense {
            payment = PaymentDraft(expense: expense)
            hadExpense = true
            countInBudget = true
        } else {
            payment.categoryID = Self.categoryName(for: r.kind).flatMap { trip.category(named: $0)?.objectID }
            payment.isSettled = false
        }
        reservationKind = r.kind
        title = r.title ?? ""
        hasDates = r.startDate != nil
        start = r.startDate ?? start
        end = r.endDate ?? end
        confirmation = r.confirmationNumber ?? ""
        provider = r.provider ?? ""
        amountText = r.amount > 0 ? Fmt.number(r.amount) : ""
        currency = r.currencyCode
        note = r.note ?? ""
        pnr = r.pnr ?? ""
        passengers = r.passengers ?? ""
        flights = r.segmentList.map { s in
            FlightDraft(objectID: s.objectID, flightNumber: s.flightNumber ?? "", airlineCode: s.airlineCode ?? "",
                        airlineName: s.airlineName ?? "", departureIATA: s.departureIATA ?? "", arrivalIATA: s.arrivalIATA ?? "",
                        departureDate: s.departureDate ?? Date(), arrivalDate: s.arrivalDate ?? Date(),
                        departureTZ: s.departureZone.identifier, arrivalTZ: s.arrivalZone.identifier,
                        terminal: s.terminal ?? "", seat: s.seat ?? "", cabinClass: s.cabinClass ?? "", baggage: s.baggage ?? "")
        }
        attachments = r.attachmentList.compactMap { a in
            guard let data = a.data else { return nil }
            return AttachmentDraft(objectID: a.objectID, data: data, kind: a.mimeKind ?? "image", name: a.name ?? "Document")
        }
    }

    private func defaultFlight() -> FlightDraft {
        var f = FlightDraft()
        f.departureIATA = "CDG"
        f.departureTZ = "Europe/Paris"
        f.arrivalTZ = trip.tripTimeZone.identifier
        let day = trip.startDate ?? Date()
        f.departureDate = DayKey.combine(dayKey: DayKey.key(day), hour: 10, minute: 30, timeZone: f.departureZone) ?? day
        f.arrivalDate = f.departureDate.addingTimeInterval(9.5 * 3600)
        return f
    }

    private func save() {
        let r: Reservation
        if let reservationID, let existing = try? context.existingObject(with: reservationID) as? Reservation {
            r = existing
        } else {
            r = context.make(Reservation.self, trip: trip)
            r.trip = trip
        }
        r.kindRaw = reservationKind.rawValue
        let firstFlight = flights.first
        r.title = title.isEmpty ? (reservationKind == .flight ? "Vol \(firstFlight?.departureIATA ?? "") → \(firstFlight?.arrivalIATA ?? "")" : reservationKind.label) : title
        r.confirmationNumber = confirmation
        r.provider = provider
        r.amount = Money.parse(amountText) ?? 0
        r.currency = currency
        r.note = note
        r.pnr = pnr
        r.passengers = passengers
        if reservationKind == .flight {
            r.startDate = flights.map(\.departureDate).min()
            r.endDate = flights.map(\.arrivalDate).max()
        } else {
            r.startDate = hasDates ? start : nil
            r.endDate = hasDates ? end : nil
        }

        // Trajets
        let keptFlights = reservationKind == .flight ? flights : []
        let keptFlightIDs = Set(keptFlights.compactMap(\.objectID))
        for s in r.segmentList where !keptFlightIDs.contains(s.objectID) { context.delete(s) }
        for (i, f) in keptFlights.enumerated() {
            let s: FlightSegment
            if let id = f.objectID, let existing = try? context.existingObject(with: id) as? FlightSegment { s = existing }
            else { s = context.make(FlightSegment.self, trip: trip); s.reservation = r }
            s.flightNumber = f.flightNumber.uppercased()
            let code = f.airlineCode.isEmpty ? (Airlines.code(fromFlightNumber: f.flightNumber) ?? "") : f.airlineCode.uppercased()
            s.airlineCode = code
            s.airlineName = f.airlineName.isEmpty ? Airlines.name(for: code) : f.airlineName
            s.departureIATA = f.departureIATA.uppercased()
            s.arrivalIATA = f.arrivalIATA.uppercased()
            s.departureDate = f.departureDate
            s.arrivalDate = f.arrivalDate
            s.departureTZ = f.departureTZ
            s.arrivalTZ = f.arrivalTZ
            s.terminal = f.terminal
            s.seat = f.seat
            s.cabinClass = f.cabinClass
            s.baggage = f.baggage
            s.sortIndex = Int32(i)
        }

        // Pièces jointes
        let keptAttachmentIDs = Set(attachments.compactMap(\.objectID))
        for a in r.attachmentList where !keptAttachmentIDs.contains(a.objectID) { context.delete(a) }
        for (i, draft) in attachments.enumerated() {
            let a: Attachment
            if let id = draft.objectID, let existing = try? context.existingObject(with: id) as? Attachment { a = existing }
            else { a = context.make(Attachment.self, trip: trip); a.reservation = r; a.data = draft.data }
            a.mimeKind = draft.kind
            a.name = draft.name
            a.sortIndex = Int32(i)
        }

        // Dépense liée (alimente le budget)
        if countInBudget && r.amount > 0 {
            let expense: Expense
            if let existing = r.expense {
                expense = existing
            } else {
                expense = context.make(Expense.self, trip: trip)
                expense.trip = trip
                expense.reservation = r
            }
            let sameCurrency = expense.currency == currency && expense.amount > 0
            let rate = currency == "EUR" ? 1 : (sameCurrency ? expense.rateUsed : rates.rate(for: currency))
            expense.title = r.wTitle
            expense.amount = r.amount
            expense.currency = currency
            expense.rateUsed = rate
            expense.amountEUR = Money.toEUR(r.amount, currency: currency, rateEURPerUnit: rate)
            expense.date = paymentDate
            if expense.merchant == nil, !provider.isEmpty { expense.merchant = provider }
            PaymentSync.apply(payment, to: expense, currency: currency, trip: trip, rates: rates, context: context)
        } else if hadExpense, !countInBudget, let existing = r.expense {
            context.delete(existing)
        }

        context.saveIfNeeded()
        dismiss()
    }
}

/// Saisie d'un trajet : heures en heure locale de chaque aéroport.
struct FlightDraftSection: View {
    @Binding var draft: FlightDraft
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        Section {
            TextField("Numéro de vol (ex. AF 090)", text: $draft.flightNumber)
                .textInputAutocapitalization(.characters)
                .onChange(of: draft.flightNumber) { _, number in
                    if let code = Airlines.code(fromFlightNumber: number) {
                        draft.airlineCode = code
                        draft.airlineName = Airlines.name(for: code) ?? draft.airlineName
                    }
                }
            LabeledContent("Compagnie", value: draft.airlineName.isEmpty ? "—" : draft.airlineName)
            HStack {
                TextField("Départ (IATA)", text: $draft.departureIATA).textInputAutocapitalization(.characters)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Arrivée (IATA)", text: $draft.arrivalIATA).textInputAutocapitalization(.characters)
            }
            .onChange(of: draft.departureIATA) { _, code in
                if let tz = Airports.timeZoneID(for: code), tz != draft.departureTZ, let zone = TimeZone(identifier: tz) {
                    draft.departureDate = FlightTime.keepWallTime(draft.departureDate, from: draft.departureZone, to: zone)
                    draft.departureTZ = tz
                }
            }
            .onChange(of: draft.arrivalIATA) { _, code in
                if let tz = Airports.timeZoneID(for: code), tz != draft.arrivalTZ, let zone = TimeZone(identifier: tz) {
                    draft.arrivalDate = FlightTime.keepWallTime(draft.arrivalDate, from: draft.arrivalZone, to: zone)
                    draft.arrivalTZ = tz
                }
            }
            DatePicker("Départ (\(shortZone(draft.departureZone)))", selection: $draft.departureDate)
                .environment(\.timeZone, draft.departureZone)
            DatePicker("Arrivée (\(shortZone(draft.arrivalZone)))", selection: $draft.arrivalDate)
                .environment(\.timeZone, draft.arrivalZone)
            LabeledContent("Durée", value: FlightTime.durationText(FlightTime.duration(departure: draft.departureDate, arrival: draft.arrivalDate)))
            TextField("Terminal", text: $draft.terminal)
            TextField("Siège", text: $draft.seat)
            TextField("Classe", text: $draft.cabinClass)
            TextField("Bagages", text: $draft.baggage)
            Button("Retirer ce trajet", role: .destructive, action: onDelete)
        } header: {
            Text("Trajet \(index + 1)")
        } footer: {
            if Airports.timeZoneID(for: draft.departureIATA) == nil || Airports.timeZoneID(for: draft.arrivalIATA) == nil {
                Text("Aéroport inconnu : ajoutez son fuseau dans Réglages > Aéroports personnalisés pour des heures locales exactes.")
            }
        }
    }

    private func shortZone(_ zone: TimeZone) -> String {
        zone.localizedName(for: .shortGeneric, locale: SharedLocale.fr) ?? zone.identifier
    }
}
