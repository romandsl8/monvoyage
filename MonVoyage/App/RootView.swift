import SwiftUI
import CoreData
import Combine

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var affluence: AffluenceService
    @EnvironmentObject private var settings: AppSettings

    /// Voyage ouvert (URI Core Data), conservé par la scène.
    @SceneStorage("openTripURI") private var openTripURI = ""
    @State private var didAutoOpen = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let error = PersistenceController.shared.loadError {
                PersistenceErrorView(error: error)
            } else if let trip = openTrip {
                TripRootView(trip: trip, onClose: { openTripURI = "" })
                    .id(trip.objectID)
                    .transition(.opacity)
            } else {
                TripListView(onOpen: open)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: openTripURI)
        .onAppear(perform: autoOpenIfTraveling)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { becameActive() }
        }
        .onChange(of: router.quickAddRequested) { _, requested in
            if requested && openTrip == nil, let trip = TripFactory.currentOrNextTrip(in: context) { open(trip) }
        }
        .onOpenURL { url in router.handle(url: url) }
        .onReceive(NotificationCenter.default.publisher(for: .monVoyageDataDidChange).receive(on: RunLoop.main)) { _ in scheduleSideEffects() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in scheduleSideEffects() }
        .task(id: router.pendingImportURL) { importPendingArchive() }
        .alert("MonVoyage", isPresented: Binding(get: { router.alertMessage != nil }, set: { if !$0 { router.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
    }

    private var openTrip: Trip? {
        guard !openTripURI.isEmpty, let url = URL(string: openTripURI),
              let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let trip = try? context.existingObject(with: id) as? Trip, !trip.isDeleted else { return nil }
        return trip
    }

    private func open(_ trip: Trip) {
        if trip.objectID.isTemporaryID { context.saveIfNeeded() }
        openTripURI = trip.objectID.uriRepresentation().absoluteString
    }

    /// Pendant les dates du voyage, l'appli s'ouvre sur la vue « Aujourd'hui ».
    private func autoOpenIfTraveling() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        if openTrip == nil, let trip = TripFactory.fetchTrips(in: context).first(where: { $0.isOngoing() }) {
            UserDefaults.standard.set(TripModule.today.rawValue, forKey: "pendingModule")
            open(trip)
        }
    }

    private func becameActive() {
        router.checkPendingQuickAdd()
        Task {
            await NotificationScheduler.requestAuthorization()
            await rates.refreshIfNeeded()
            await affluence.refresh()
            await LiveActivityManager.refresh(context: context)
            WidgetSnapshotWriter.update(context: context)
            await NotificationScheduler.reschedule(context: context, settings: settings)
        }
        BackgroundRefresh.schedule()
    }

    /// Notifications + widget recalculés après une modification (regroupées).
    private func scheduleSideEffects() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            WidgetSnapshotWriter.update(context: context)
            await NotificationScheduler.reschedule(context: context, settings: settings)
        }
    }

    private func importPendingArchive() {
        guard let url = router.pendingImportURL else { return }
        router.pendingImportURL = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let trips = try ExportImportService.importArchive(data, into: context)
            router.alertMessage = trips.count == 1 ? "Voyage « \(trips[0].wName) » importé." : "\(trips.count) voyages importés."
        } catch {
            router.alertMessage = "Import impossible : \(error.localizedDescription)"
        }
    }
}
