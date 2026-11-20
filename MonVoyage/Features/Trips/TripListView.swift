import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Accueil : liste des voyages.
struct TripListView: View {
    let onOpen: (Trip) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: true)], animation: .default)
    private var trips: FetchedResults<Trip>

    @State private var showNewTrip = false
    @State private var showSettings = false
    @State private var showArchived = false
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var tripToDelete: Trip?

    private var active: [Trip] { trips.filter { !$0.archived } }
    private var archived: [Trip] { trips.filter { $0.archived } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if settings.shouldRemindExport && !trips.isEmpty {
                        exportReminder
                    }
                    if active.isEmpty {
                        EmptyState(symbol: "suitcase.rolling.fill", title: "Aucun voyage",
                                   message: "Créez votre premier voyage pour préparer le budget, le planning et les réservations.",
                                   actionTitle: "Créer un voyage") { showNewTrip = true }
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(active, id: \.objectID) { trip in
                                tripCard(trip)
                            }
                        }
                    }
                    if !archived.isEmpty {
                        DisclosureGroup("Voyages archivés (\(archived.count))", isExpanded: $showArchived) {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(archived, id: \.objectID) { trip in tripCard(trip) }
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
            .groupedBackground()
            .navigationTitle("Mes voyages")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Label("Réglages", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNewTrip = true } label: { Label("Nouveau voyage", systemImage: "plus") }
                        Button { showImporter = true } label: { Label("Importer une archive", systemImage: "square.and.arrow.down") }
                        Button { exportAll() } label: { Label("Exporter tous les voyages", systemImage: "square.and.arrow.up") }
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewTrip) {
                TripEditorView(trip: nil, onCreated: { trip in onOpen(trip) })
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView()
            }
            .sheet(item: Binding(get: { exportURL.map(ShareableURL.init) }, set: { exportURL = $0?.url })) { item in
                ShareSheet(items: [item.url])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
                if case .success(let url) = result { router.pendingImportURL = url }
            }
            .confirmationDialog("Supprimer ce voyage ?", isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }), titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) {
                    if let trip = tripToDelete { context.delete(trip); context.saveIfNeeded() }
                    tripToDelete = nil
                }
            } message: {
                Text("Le voyage et tout son contenu seront supprimés sur tous vos appareils. Pensez à l'exporter avant.")
            }
        }
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)] : [GridItem(.flexible())]
    }

    private var exportReminder: some View {
        Card {
            HStack(alignment: .top) {
                Image(systemName: "externaldrive.badge.timemachine").foregroundStyle(.orange).font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sauvegarde conseillée").font(.subheadline.bold())
                    Text("Aucun export depuis plus de 30 jours. Vos données sont dans iCloud, mais une copie dans Fichiers ne coûte rien.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Exporter") { exportAll() }.buttonStyle(.glass)
                        Button("Plus tard") { settings.exportReminderDismissedAt = Date() }.font(.caption)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func tripCard(_ trip: Trip) -> some View {
        Button { onOpen(trip) } label: { TripCardView(trip: trip) }
            .buttonStyle(.plain)
            .contextMenu {
                Button { onOpen(trip) } label: { Label("Ouvrir", systemImage: "arrow.forward.circle") }
                Button { try? ExportImportService.duplicate(trip, in: context) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                Button { export([trip]) } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                Button {
                    trip.archived.toggle()
                    context.saveIfNeeded()
                } label: {
                    Label(trip.archived ? "Désarchiver" : "Archiver", systemImage: "archivebox")
                }
                Divider()
                Button(role: .destructive) { tripToDelete = trip } label: { Label("Supprimer", systemImage: "trash") }
            }
    }

    private func exportAll() { export(Array(trips)) }

    private func export(_ list: [Trip]) {
        do {
            exportURL = try ExportImportService.exportFile(trips: list)
            settings.lastExportDate = Date()
        } catch {
            router.alertMessage = "Export impossible : \(error.localizedDescription)"
        }
    }
}

/// Carte d'un voyage dans la liste.
struct TripCardView: View {
    @ObservedObject var trip: Trip

    var body: some View {
        let summary = BudgetSummary(trip: trip)
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.wName).font(.title3.bold()).fontDesign(.rounded)
                    if let city = trip.city, !city.isEmpty {
                        Label(city, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let start = trip.startDate, let end = trip.endDate {
                        Text("\(Fmt.day(start)) → \(Fmt.day(end))").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                countdown
            }
            if summary.budgetEUR > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressBar(fraction: summary.consumedFraction, tint: trip.accent)
                    Text("\(Fmt.eurShort(summary.plannedEUR)) sur \(Fmt.eurShort(summary.budgetEUR))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if CloudSharing.isShared(trip) {
                GlassChip(text: CloudSharing.isParticipant(trip) ? "Partagé avec moi" : "Partagé", symbol: "person.2.fill", tint: trip.accent)
            }
        }
        .overlay(alignment: .leading) {
            Capsule().fill(trip.accent).frame(width: 5).padding(.vertical, 18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le voyage")
    }

    @ViewBuilder
    private var countdown: some View {
        if trip.isOngoing() {
            GlassChip(text: "En cours", symbol: "airplane.departure", tint: trip.accent)
        } else if trip.isFinished() {
            Text("Terminé").font(.caption).foregroundStyle(.secondary)
        } else if let days = trip.daysUntilDeparture() {
            VStack(spacing: 0) {
                Text("J-\(max(0, days))").font(.title.bold()).fontDesign(.rounded).foregroundStyle(trip.accent)
                Text(days <= 1 ? "jour" : "jours").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Départ dans \(days) jours")
        }
    }
}

struct ShareableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Feuille de partage système (Fichiers, AirDrop…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
