import SwiftUI
import CloudKit
import UIKit

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

                SharedWithMeSection()

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
    @State private var accountStatus = "…"

    private var compilation: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private var cloudKitEnvironment: String {
        (Bundle.main.object(forInfoDictionaryKey: "CloudKitEnvironment") as? String) ?? "inconnu"
    }

    var body: some View {
        Form {
            Section("Diagnostic") {
                LabeledContent("Conteneur", value: PersistenceController.cloudKitContainerID)
                LabeledContent("Environnement CloudKit", value: cloudKitEnvironment)
                LabeledContent("Compilation", value: compilation)
                LabeledContent("Compte iCloud", value: accountStatus)
                LabeledContent("Magasin privé", value: PersistenceController.shared.privateStore == nil ? "non chargé" : "chargé")
                LabeledContent("Magasin partagé", value: PersistenceController.shared.sharedStore == nil ? "non chargé" : "chargé")
            }
            Section {
                Button {
                    running = true
                    message = nil
                    let controller = PersistenceController.shared
                    DispatchQueue.global(qos: .userInitiated).async {
                        var result: String
                        do {
                            try controller.initializeCloudKitSchema()
                            result = "✅ Schéma envoyé dans l'environnement Development. Déployez-le maintenant vers Production dans la console CloudKit."
                        } catch {
                            result = "Échec.\n\n" + CloudKitErrorReport.describe(error)
                        }
                        DispatchQueue.main.async {
                            message = result
                            running = false
                        }
                    }
                } label: {
                    HStack { Text("Initialiser le schéma CloudKit"); if running { Spacer(); ProgressView() } }
                }
                .disabled(running)
            } footer: {
                Text("À faire une seule fois, sur un build compilé avec CLOUDKIT_ENV = Development, avec un compte iCloud connecté. L'opération peut prendre une minute.")
            }
            if let message {
                Section {
                    Text(message).font(.footnote.monospaced()).textSelection(.enabled)
                    Button { UIPasteboard.general.string = message } label: { Label("Copier le message", systemImage: "doc.on.doc") }
                }
            }
        }
        .navigationTitle("CloudKit")
        .task { accountStatus = await CloudKitErrorReport.accountStatus() }
    }
}

/// Description détaillée d'une erreur Core Data / CloudKit (pour le dépannage).
enum CloudKitErrorReport {
    static func describe(_ error: Error, depth: Int = 0) -> String {
        let ns = error as NSError
        let indent = String(repeating: "  ", count: depth)
        var lines = ["\(indent)\(ns.domain) \(ns.code) : \(ns.localizedDescription)"]
        let useful: Set<String> = ["ServerErrorDescription", "NSDebugDescription", "CKErrorDescription"]
        for (key, value) in ns.userInfo where key != NSUnderlyingErrorKey && key != CKPartialErrorsByItemIDKey {
            if depth > 0 && !useful.contains(key) { continue }
            let text = String(describing: value)
            lines.append("\(indent)  \(key) = \(text.prefix(400))")
        }
        if let partial = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            // « Atomic failure » (22) n'est qu'une conséquence : on montre d'abord la vraie cause.
            let causes = partial.filter { ($0.value as NSError).code != CKError.batchRequestFailed.rawValue }
            let atomic = partial.count - causes.count
            lines.append("\(indent)  \(partial.count) élément(s) refusé(s), dont \(atomic) par simple effet de lot.")
            for (item, sub) in causes.prefix(3) {
                var name = String(describing: item)
                if let id = item as? CKRecord.ID { name = id.recordName }
                lines.append("\(indent)  ⚠️ cause, élément \(name) :")
                lines.append(describe(sub, depth: depth + 2))
            }
            if causes.isEmpty, let first = partial.first {
                let item = first.key, sub = first.value
                let name = (item as? CKRecord.ID)?.recordName ?? String(describing: item)
                lines.append("\(indent)  élément \(name) :")
                lines.append(describe(sub, depth: depth + 2))
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error, depth < 4 {
            lines.append(describe(underlying, depth: depth + 1))
        }
        return lines.joined(separator: "\n")
    }

    static func accountStatus() async -> String {
        do {
            let status = try await CKContainer(identifier: PersistenceController.cloudKitContainerID).accountStatus()
            switch status {
            case .available: return "connecté"
            case .noAccount: return "aucun compte"
            case .restricted: return "restreint"
            case .temporarilyUnavailable: return "temporairement indisponible"
            case .couldNotDetermine: return "indéterminé"
            @unknown default: return "inconnu"
            }
        } catch {
            return "erreur : \(error.localizedDescription)"
        }
    }
}

/// Invité : vérifier les voyages partagés avec moi, ou rejoindre en collant le lien d'invitation.
struct SharedWithMeSection: View {
    @State private var linkText = ""
    @State private var report: String?
    @State private var busy = false

    private var link: URL? {
        let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", url.host?.hasSuffix("icloud.com") == true else { return nil }
        return url
    }

    var body: some View {
        Section {
            Button {
                Task {
                    busy = true
                    defer { busy = false }
                    report = await CloudSharing.sharedWithMeReport()
                }
            } label: {
                HStack { Label("Vérifier les voyages partagés avec moi", systemImage: "checkmark.icloud"); if busy { Spacer(); ProgressView() } }
            }
            .disabled(busy)
            HStack {
                TextField("Coller le lien d'invitation", text: $linkText)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Coller") { linkText = UIPasteboard.general.string ?? linkText }
                    .buttonStyle(.borderless)
            }
            Button {
                guard let link else { return }
                Task {
                    busy = true
                    defer { busy = false }
                    do { report = try await CloudSharing.join(link: link); linkText = "" }
                    catch { report = "Impossible de rejoindre le voyage : \(error.localizedDescription)" }
                }
            } label: { Label("Rejoindre le voyage", systemImage: "person.2.badge.plus") }
            .disabled(busy || link == nil)
            if let report {
                Text(report).font(.footnote).textSelection(.enabled)
            }
        } header: { Text("Voyages partagés avec moi") } footer: {
            Text("Si toucher le lien d'invitation n'a rien affiché, collez-le ici. Le voyage apparaît ensuite dans Mes voyages après la synchronisation iCloud (jusqu'à une minute).")
        }
    }
}
