import SwiftUI

/// Réglages de l'appli : taux forcé, affluence, rappels, tables aéroports / compagnies, version.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var affluence: AffluenceService
    @EnvironmentObject private var settings: AppSettings

    @State private var manualRateText = ""
    @State private var versionTaps = 0
    @State private var showDebug = false
    @State private var newAirport = ""
    @State private var newAirportTZ = ""
    @State private var newAirline = ""
    @State private var newAirlineName = ""
    @State private var newCheckIn = ""
    @State private var customAirports = Airports.custom
    @State private var customAirlines = Airlines.custom

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("1 $ =", value: "\(Fmt.number(rates.usdToEUR, digits: 4)) €")
                    Text(rates.isManual ? "Taux saisi manuellement" : "Taux BCE (Frankfurter) · \(Fmt.updated(rates.updatedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = rates.lastError, !rates.isManual {
                        Text("Dernière mise à jour impossible : \(error)").font(.caption).foregroundStyle(.orange)
                    }
                    AmountField(title: "Forcer le taux (€ pour 1 $)", text: $manualRateText)
                    HStack {
                        Button("Appliquer") { rates.manualRate = Money.parse(manualRateText) }
                            .disabled(Money.parse(manualRateText) == nil)
                        Spacer()
                        Button("Taux automatique") { rates.manualRate = nil; manualRateText = ""; Task { await rates.refreshIfNeeded(force: true) } }
                    }
                    .buttonStyle(.borderless)
                } header: { Text("Taux de change") }

                Section {
                    TextField("URL de affluence.json", text: $affluence.urlString)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Mettre à jour maintenant") { Task { await affluence.refresh(force: true) } }
                    if let cache = affluence.cache {
                        Text("\(cache.file.source) · \(Fmt.updated(cache.fetchedAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = affluence.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                } header: { Text("Affluence des parcs") } footer: {
                    Text("Fichier publié chaque jour par votre workflow GitHub. Sans fichier, saisissez l'affluence à la main dans Parcs.")
                }

                Section("Rappels") {
                    Toggle("Notifications", isOn: $settings.notificationsEnabled)
                    Stepper("Départ pour l'aéroport : \(settings.airportLeadHours) h avant", value: $settings.airportLeadHours, in: 1...6)
                    Stepper("Rappel ESTA : \(settings.estaReminderDays) j avant", value: $settings.estaReminderDays, in: 7...120, step: 1)
                }

                Section {
                    ForEach(customAirports.keys.sorted(), id: \.self) { code in
                        LabeledContent(code, value: customAirports[code] ?? "")
                    }
                    .onDelete { offsets in
                        let keys = customAirports.keys.sorted()
                        for i in offsets { customAirports.removeValue(forKey: keys[i]) }
                        Airports.custom = customAirports
                    }
                    TextField("Code IATA (ex. SFB)", text: $newAirport).textInputAutocapitalization(.characters)
                    TextField("Fuseau (ex. America/New_York)", text: $newAirportTZ).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Ajouter l'aéroport") {
                        let code = newAirport.uppercased().trimmingCharacters(in: .whitespaces)
                        guard code.count == 3, TimeZone(identifier: newAirportTZ) != nil else { return }
                        customAirports[code] = newAirportTZ
                        Airports.custom = customAirports
                        newAirport = ""; newAirportTZ = ""
                    }
                } header: { Text("Aéroports personnalisés") } footer: {
                    Text("\(Airports.builtIn.count) aéroports sont déjà connus. Ajoutez ici ceux qui manquent.")
                }

                Section {
                    ForEach(customAirlines.keys.sorted(), id: \.self) { code in
                        LabeledContent(code, value: "\(customAirlines[code] ?? "") · enregistrement \(Airlines.checkInHours(for: code)) h avant")
                    }
                    .onDelete { offsets in
                        let keys = customAirlines.keys.sorted()
                        for i in offsets { customAirlines.removeValue(forKey: keys[i]) }
                        Airlines.custom = customAirlines
                    }
                    TextField("Code (ex. AF)", text: $newAirline).textInputAutocapitalization(.characters)
                    TextField("Nom de la compagnie", text: $newAirlineName)
                    TextField("Ouverture de l'enregistrement (heures)", text: $newCheckIn).keyboardType(.numberPad)
                    Button("Ajouter / modifier la compagnie") {
                        let code = newAirline.uppercased().trimmingCharacters(in: .whitespaces)
                        guard code.count == 2 else { return }
                        if !newAirlineName.isEmpty { customAirlines[code] = newAirlineName; Airlines.custom = customAirlines }
                        if let hours = Int(newCheckIn) { var c = Airlines.customCheckIn; c[code] = hours; Airlines.customCheckIn = c }
                        newAirline = ""; newAirlineName = ""; newCheckIn = ""
                    }
                } header: { Text("Compagnies aériennes") }

                Section {
                    Button { versionTaps += 1; if versionTaps >= 5 { versionTaps = 0; showDebug = true } } label: {
                        LabeledContent("Version", value: AppSettings.appVersion)
                    }
                    .foregroundStyle(.primary)
                    Text("Données météo : Open-Meteo.com · Taux : BCE via Frankfurter · Attractions : Powered by Queue-Times.com")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .navigationDestination(isPresented: $showDebug) { CloudKitDebugView() }
            .onAppear { if let m = rates.manualRate { manualRateText = Fmt.number(m, digits: 4) } }
        }
    }
}

/// Écran caché (5 appuis sur la version) : initialisation du schéma CloudKit.
struct CloudKitDebugView: View {
    @State private var message: String?
    @State private var running = false

    private var environment: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Conteneur", value: PersistenceController.cloudKitContainerID)
                LabeledContent("Compilation", value: environment)
            }
            Section {
                Button {
                    running = true
                    do {
                        try PersistenceController.shared.initializeCloudKitSchema()
                        message = "Schéma envoyé dans l'environnement Development. Déployez-le maintenant vers Production dans la console CloudKit."
                    } catch {
                        message = "Échec : \(error.localizedDescription)\n\nCe bouton ne fonctionne que sur un build compilé avec CLOUDKIT_ENV = Development."
                    }
                    running = false
                } label: {
                    HStack { Text("Initialiser le schéma CloudKit"); if running { Spacer(); ProgressView() } }
                }
            } footer: {
                Text("À faire une seule fois, sur le premier build TestFlight compilé en Development, avec un compte iCloud connecté. L'opération peut prendre une minute.")
            }
            if let message {
                Section { Text(message).font(.footnote).textSelection(.enabled) }
            }
        }
        .navigationTitle("CloudKit")
    }
}
