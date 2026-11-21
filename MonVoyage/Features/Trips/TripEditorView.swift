import SwiftUI
import CoreData

/// Création / modification d'un voyage. Le brouillon vit dans @State de la feuille,
/// qui est présentée au-dessus de la mise en page : plier/déplier ne perd rien.
struct TripEditorView: View {
    let trip: Trip?
    var onCreated: ((Trip) -> Void)? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var queueTimes: QueueTimesService

    @State private var name = ""
    @State private var city = ""
    @State private var country = ""
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var start = Date().addingTimeInterval(30 * 86400)
    @State private var end = Date().addingTimeInterval(44 * 86400)
    @State private var accentHex = AccentPalette.colors[0]
    @State private var budget = ""
    @State private var currency = "USD"
    @State private var taxPercent = "6,5"
    @State private var tipPercent = "20"
    @State private var preFees = ""
    @State private var postFees = ""
    @State private var selectedParks: [QTPark] = []
    @State private var showParkPicker = false
    @State private var showCitySearch = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Voyage") {
                    TextField("Nom (ex. Floride 2027)", text: $name)
                    Button {
                        showCitySearch = true
                    } label: {
                        HStack {
                            Text("Destination").foregroundStyle(.primary)
                            Spacer()
                            Text(city.isEmpty ? "Rechercher une ville" : "\(city)\(country.isEmpty ? "" : ", \(country)")")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !city.isEmpty {
                        LabeledContent("Fuseau horaire", value: timeZoneID)
                    }
                    DatePicker("Début", selection: $start, displayedComponents: .date)
                    DatePicker("Fin", selection: $end, in: start..., displayedComponents: .date)
                }
                Section("Couleur") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(AccentPalette.colors, id: \.self) { hex in
                                Circle().fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay { if hex == accentHex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                    .onTapGesture { accentHex = hex }
                                    .accessibilityLabel("Couleur \(hex)")
                                    .accessibilityAddTraits(hex == accentHex ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    AmountField(title: "Budget total", text: $budget, currency: "EUR")
                    Picker("Devise locale", selection: $currency) {
                        Text("Dollar US (USD)").tag("USD")
                        Text("Euro (EUR)").tag("EUR")
                    }
                    AmountField(title: "Taxe locale (%)", text: $taxPercent)
                    AmountField(title: "Pourboire par défaut (%)", text: $tipPercent)
                } header: {
                    Text("Budget")
                } footer: {
                    Text("Montants en euros. La taxe de vente est ajoutée aux prix affichés hors taxe (6,5 % à Orlando).")
                }
                Section {
                    AmountField(title: "Frais avant départ", text: $preFees, currency: "EUR")
                    AmountField(title: "Frais après retour", text: $postFees, currency: "EUR")
                } header: {
                    Text("Hors séjour")
                } footer: {
                    Text("Ces frais (parking, transport vers l'aéroport…) sont exclus du budget restant par jour.")
                }
                Section {
                    ForEach(selectedParks) { park in
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(Color(hex: accentHex))
                            Text(park.name)
                            Spacer()
                            Button {
                                selectedParks.removeAll { $0.id == park.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Retirer \(park.name)")
                        }
                    }
                    Button {
                        showParkPicker = true
                    } label: {
                        Label(selectedParks.isEmpty ? "Choisir les parcs" : "Modifier la sélection", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Parcs")
                } footer: {
                    Text(trip == nil
                         ? "Disney, Universal, Six Flags, Europa-Park… Les temps d'attente en direct s'afficheront pour ces parcs. Facultatif : vous pourrez en ajouter plus tard."
                         : "Parcs à ajouter au voyage. Pour en retirer, allez dans Parcs › Ma liste.")
                }
            }
            .navigationTitle(trip == nil ? "Nouveau voyage" : "Modifier le voyage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCitySearch) {
                CitySearchView { result in
                    city = result.name
                    country = result.country ?? ""
                    latitude = result.latitude
                    longitude = result.longitude
                    timeZoneID = result.timezone ?? timeZoneID
                }
            }
            .sheet(isPresented: $showParkPicker) {
                ParkMultiPicker(selection: $selectedParks,
                                alreadyAdded: Set(trip?.parkList.map(\.queueTimesID).filter { $0 > 0 } ?? []))
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let trip else { return }
        name = trip.name ?? ""
        city = trip.city ?? ""
        country = trip.country ?? ""
        latitude = trip.latitude
        longitude = trip.longitude
        timeZoneID = trip.timeZoneID ?? TimeZone.current.identifier
        start = trip.startDate ?? start
        end = trip.endDate ?? end
        accentHex = trip.accentHex ?? accentHex
        budget = trip.totalBudgetEUR > 0 ? Fmt.number(trip.totalBudgetEUR) : ""
        currency = trip.currencyCode
        taxPercent = Fmt.number(trip.taxRate * 100, digits: 3)
        tipPercent = Fmt.number(trip.defaultTipRate * 100, digits: 2)
        preFees = trip.preDepartureFeesEUR > 0 ? Fmt.number(trip.preDepartureFeesEUR) : ""
        postFees = trip.postDepartureFeesEUR > 0 ? Fmt.number(trip.postDepartureFeesEUR) : ""
    }

    private func save() {
        let target = trip ?? TripFactory.createTrip(in: context)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.city = city
        target.country = country
        target.latitude = latitude
        target.longitude = longitude
        target.timeZoneID = timeZoneID
        target.startDate = DayKey.noon(start)
        target.endDate = DayKey.noon(max(start, end))
        target.accentHex = accentHex
        target.totalBudgetEUR = Money.parse(budget) ?? 0
        target.localCurrency = currency
        target.taxRate = (Money.parse(taxPercent) ?? 6.5) / 100
        target.defaultTipRate = (Money.parse(tipPercent) ?? 20) / 100
        target.preDepartureFeesEUR = Money.parse(preFees) ?? 0
        target.postDepartureFeesEUR = Money.parse(postFees) ?? 0
        if !selectedParks.isEmpty {
            TripFactory.addParks(selectedParks, to: target, in: context)
        }
        context.saveIfNeeded()
        if trip == nil { onCreated?(target) }
        dismiss()
    }
}

/// Recherche de ville (géocodage Open-Meteo : coordonnées + fuseau).
struct CitySearchView: View {
    let onSelect: (GeocodingResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var error: String?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        onSelect(result)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.name).foregroundStyle(.primary)
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if searching { ProgressView() }
                else if results.isEmpty && error == nil {
                    ContentUnavailableView("Rechercher une ville", systemImage: "magnifyingglass",
                                           description: Text("Exemple : Orlando. Hors ligne, vous pourrez la renseigner plus tard."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ville")
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await search()
            }
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
    }

    private func search() async {
        guard query.count >= 2 else { results = []; return }
        searching = true
        defer { searching = false }
        do {
            results = try await WeatherService.searchCity(query)
            error = results.isEmpty ? "Aucune ville trouvée." : nil
        } catch {
            self.error = "Recherche impossible hors ligne."
        }
    }
}
