import SwiftUI
import CoreData

/// Onglet Parcs : temps d'attente en direct (tous les parcs) ou ma liste par parc.
struct ParksView: View {
    @ObservedObject var trip: Trip
    @SceneStorage("parks.mode") private var mode = "waits"
    @State private var showAddPark = false

    var body: some View {
        Group {
            if mode == "waits" {
                WaitTimesBoard(trip: trip)
            } else {
                ParksListView(trip: trip)
            }
        }
        .navigationTitle("Parcs et attractions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddPark) { ParkPickerView(trip: trip) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Affichage", selection: $mode) {
                    Text("Temps d'attente").tag("waits")
                    Text("Ma liste").tag("list")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddPark = true } label: { Label("Ajouter des parcs", systemImage: "plus") }
            }
        }
    }
}

/// Parcs du voyage, affluence (saisie manuelle possible) et attractions à faire.
struct ParksListView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var queueTimes: QueueTimesService
    @ObservedObject private var hours = ParkHoursService.shared
    @State private var showAddPark = false

    var body: some View {
        List {
            if trip.parkList.isEmpty {
                EmptyState(symbol: "sparkles", title: "Aucun parc",
                           message: "Choisissez les parcs de votre voyage : Disney, Universal, Six Flags, Europa-Park… plus de 100 parcs avec temps d'attente en direct.",
                           actionTitle: "Choisir les parcs") { showAddPark = true }
                .listRowBackground(Color.clear)
            }
            ForEach(trip.parkList, id: \.objectID) { park in
                NavigationLink {
                    ParkDetailView(park: park, trip: trip)
                } label: {
                    let progress = park.mustDoProgress
                    HStack(spacing: 12) {
                    ParkPhotoBackground(park: park, tint: trip.accent, compact: true)
                        .frame(width: 64, height: 48)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(park.wName).font(.headline)
                        Text(progress.total == 0 ? "\(park.attractionList.count) attraction(s)" : "\(progress.done)/\(progress.total) incontournables")
                            .font(.caption).foregroundStyle(.secondary)
                        ParkHoursBadge(schedule: hours.schedule(for: park))
                    }
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(trip.parkList[i]) }
                context.saveIfNeeded()
            }
            Section { QueueTimesCredit() }
        }
        .scrollContentBackground(.hidden)
        .groupedBackground()
        .task(id: trip.parkList.map(\.queueTimesID)) { await hours.refresh(parks: trip.parkList) }
        .sheet(isPresented: $showAddPark) { ParkPickerView(trip: trip) }
    }
}

/// Ajout de parcs à un voyage existant (sélection multiple dans la liste Queue-Times).
struct ParkPickerView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @State private var selection: [QTPark] = []

    var body: some View {
        ParkMultiPicker(selection: $selection,
                        alreadyAdded: Set(trip.parkList.map(\.queueTimesID).filter { $0 > 0 }),
                        onManualAdd: addManual)
            .onDisappear {
                guard !selection.isEmpty else { return }
                TripFactory.addParks(selection, to: trip, in: context)
                context.saveIfNeeded()
                selection = []
            }
    }

    private func addManual(_ name: String) {
        let park = context.make(Park.self, trip: trip)
        park.name = name
        park.queueTimesID = 0
        park.sortIndex = Int32(trip.parkList.count)
        park.trip = trip
        context.saveIfNeeded()
    }
}

/// Détail d'un parc : affluence manuelle, attractions, temps d'attente en direct.
struct ParkDetailView: View {
    @ObservedObject var park: Park
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var queueTimes: QueueTimesService
    @EnvironmentObject private var affluence: AffluenceService
    @State private var importing = false
    @State private var importError: String?
    @State private var editingAttraction: Attraction?
    @State private var showManualCrowd = false
    @State private var doneTick = 0
    @ObservedObject private var hours = ParkHoursService.shared

    private var waits: WaitTimesCache? { queueTimes.waitTimes[park.queueTimesID] ?? queueTimes.cachedWaits(parkID: park.queueTimesID) }

    var body: some View {
        List {
            Section {
                let progress = park.mustDoProgress
                if progress.total > 0 {
                    VStack(alignment: .leading) {
                        Text("\(progress.done)/\(progress.total) incontournables faits").font(.headline)
                        ProgressBar(fraction: Double(progress.done) / Double(progress.total), tint: trip.accent)
                    }
                }
                Button { showManualCrowd = true } label: { Label("Affluence et horaires (saisie manuelle)", systemImage: "person.3.sequence.fill") }
            }

            if park.queueTimesID > 0 {
                Section {
                    ParkHoursList(schedule: hours.schedule(for: park), tripDayKeys: trip.dayKeys, tint: trip.accent)
                } header: {
                    Label("Horaires d'ouverture", systemImage: "clock")
                }
            }

            ForEach(groupedAttractions, id: \.day) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.objectID) { attraction in
                        AttractionRow(attraction: attraction, wait: waits?.rides[attraction.queueTimesID], isOpen: waits?.open[attraction.queueTimesID],
                                      showWait: waits != nil) {
                            doneTick += 1
                        }
                        .contentShape(.rect)
                        .onTapGesture { editingAttraction = attraction }
                    }
                    .onMove { from, to in move(in: group.items, from: from, to: to) }
                    .onDelete { offsets in
                        for i in offsets { context.delete(group.items[i]) }
                        context.saveIfNeeded()
                    }
                }
            }

            Section {
                Button {
                    Task { await importAttractions() }
                } label: {
                    HStack { Label("Importer les attractions (Queue-Times)", systemImage: "square.and.arrow.down"); if importing { Spacer(); ProgressView() } }
                }
                .disabled(park.queueTimesID == 0 || importing)
                Button {
                    let a = context.make(Attraction.self, trip: trip)
                    a.name = "Nouvelle attraction"
                    a.priority = AttractionPriority.ifPossible.rawValue
                    a.sortIndex = Int32(park.attractionList.count)
                    a.park = park
                    context.saveIfNeeded()
                    editingAttraction = a
                } label: { Label("Ajouter une attraction", systemImage: "plus") }
                if let importError { Text(importError).font(.caption).foregroundStyle(.orange) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let waits { Text("Temps d'attente \(Fmt.updated(waits.updatedAt))") }
                    QueueTimesCredit()
                }
            }
        }
        .navigationTitle(park.wName)
        .scrollContentBackground(.hidden)
        .groupedBackground()
        .toolbar { EditButton() }
        .refreshable { await refreshWaits(); await hours.refresh(parks: [park], force: true) }
        .task { await hours.refresh(parks: [park]) }
        .task {
            // Temps réel : actualisation toutes les minutes tant que l'écran est affiché.
            while !Task.isCancelled {
                await refreshWaits()
                try? await Task.sleep(nanoseconds: WaitTimesBoard.refreshSeconds * 1_000_000_000)
            }
        }
        .sheet(item: $editingAttraction) { attraction in AttractionEditorView(attraction: attraction, trip: trip) }
        .sheet(isPresented: $showManualCrowd) { ManualCrowdView(park: park, trip: trip) }
        .sensoryFeedback(.success, trigger: doneTick)
    }

    private struct DayGroup { var day: String; var title: String; var items: [Attraction] }

    /// Attractions par jour assigné (dans l'ordre voulu), puis non assignées.
    private var groupedAttractions: [DayGroup] {
        var map: [String: [Attraction]] = [:]
        for a in park.attractionList {
            let key = a.assignedDay.map { DayKey.key($0) } ?? "~"
            map[key, default: []].append(a)
        }
        return map.keys.sorted().map { key in
            let title = key == "~" ? "Non planifiées" : (DayKey.date(fromKey: key).map { Fmt.longDay($0).capitalized } ?? key)
            return DayGroup(day: key, title: title, items: map[key] ?? [])
        }
    }

    private func move(in items: [Attraction], from: IndexSet, to: Int) {
        var list = items
        list.move(fromOffsets: from, toOffset: to)
        let base = list.map(\.sortIndex).min() ?? 0
        for (i, a) in list.enumerated() { a.sortIndex = base + Int32(i) }
        context.saveIfNeeded()
    }

    private func refreshWaits() async {
        guard park.queueTimesID > 0 else { return }
        await queueTimes.refreshWaits(parkID: park.queueTimesID)
    }

    private func importAttractions() async {
        importing = true
        defer { importing = false }
        do {
            let rides = try await queueTimes.fetchRides(parkID: park.queueTimesID)
            let existing = Set(park.attractionList.map(\.queueTimesID))
            var index = Int32(park.attractionList.count)
            for (area, ride) in rides where !existing.contains(ride.id) {
                let a = context.make(Attraction.self, trip: trip)
                a.name = ride.name
                a.area = area
                a.queueTimesID = ride.id
                a.priority = AttractionPriority.ifPossible.rawValue
                a.sortIndex = index
                a.park = park
                index += 1
            }
            context.saveIfNeeded()
            importError = nil
        } catch {
            importError = "Import impossible : \(error.localizedDescription)"
        }
    }
}

struct AttractionRow: View {
    @ObservedObject var attraction: Attraction
    let wait: Int?
    let isOpen: Bool?
    let showWait: Bool
    let onDone: () -> Void
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Button {
                attraction.doneDate = attraction.doneDate == nil ? Date() : nil
                context.saveIfNeeded()
                if attraction.doneDate != nil { onDone() }
            } label: {
                Image(systemName: attraction.doneDate != nil ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(attraction.doneDate != nil ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(attraction.doneDate != nil ? "Marquer non faite" : "Marquer faite")
            VStack(alignment: .leading, spacing: 2) {
                Text(attraction.wName).strikethrough(attraction.doneDate != nil)
                HStack(spacing: 6) {
                    Text(attraction.priorityValue.label).foregroundStyle(attraction.priorityValue.color)
                    if attraction.expressEligible { Label("Express", systemImage: "bolt.fill") }
                    if attraction.minHeightCm > 0 { Text("≥ \(attraction.minHeightCm) cm") }
                    if let area = attraction.area { Text(area).lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if showWait, let wait {
                if isOpen == false {
                    Text("Fermé").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(wait) min").font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(wait >= 60 ? Color.red : (wait >= 30 ? Color.orange : Color.green))
                        .accessibilityLabel("Attente \(wait) minutes")
                }
            }
        }
    }
}

struct AttractionEditorView: View {
    @ObservedObject var attraction: Attraction
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: Binding(get: { attraction.name ?? "" }, set: { attraction.name = $0 }))
                TextField("Zone", text: Binding(get: { attraction.area ?? "" }, set: { attraction.area = $0 }))
                Picker("Priorité", selection: Binding(get: { attraction.priorityValue }, set: { attraction.priority = $0.rawValue })) {
                    ForEach(AttractionPriority.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Éligible Express", isOn: Binding(get: { attraction.expressEligible }, set: { attraction.expressEligible = $0 }))
                Stepper("Taille minimale : \(attraction.minHeightCm == 0 ? "aucune" : "\(attraction.minHeightCm) cm")",
                        value: Binding(get: { Int(attraction.minHeightCm) }, set: { attraction.minHeightCm = Int16($0) }), in: 0...150, step: 5)
                Picker("Jour", selection: Binding(get: { attraction.assignedDay.map { DayKey.key($0) } ?? "" },
                                                  set: { attraction.assignedDay = $0.isEmpty ? nil : DayKey.date(fromKey: $0) })) {
                    Text("Non planifiée").tag("")
                    ForEach(trip.dayKeys, id: \.self) { key in
                        Text(DayKey.date(fromKey: key).map { Fmt.day($0) } ?? key).tag(key)
                    }
                }
                Toggle("Faite", isOn: Binding(get: { attraction.doneDate != nil }, set: { attraction.doneDate = $0 ? Date() : nil }))
                if let done = attraction.doneDate { LabeledContent("Faite le", value: Fmt.dateTime(done)) }
                TextField("Note", text: Binding(get: { attraction.note ?? "" }, set: { attraction.note = $0 }), axis: .vertical)
            }
            .navigationTitle("Attraction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { context.saveIfNeeded(); dismiss() } } }
        }
    }
}

/// Saisie manuelle de l'affluence et des horaires pour un parc et une date.
struct ManualCrowdView: View {
    @ObservedObject var park: Park
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var dayKey = ""
    @State private var level = 5
    @State private var open = "09:00"
    @State private var close = "21:00"

    var body: some View {
        NavigationStack {
            Form {
                Picker("Jour", selection: $dayKey) {
                    ForEach(trip.dayKeys, id: \.self) { key in
                        Text(DayKey.date(fromKey: key).map { Fmt.day($0) } ?? key).tag(key)
                    }
                }
                Section("Affluence") {
                    Stepper("\(level)/10 · \(CrowdScale.label(for: level))", value: $level, in: 1...10)
                        .foregroundStyle(CrowdColor.color(for: level))
                }
                Section("Horaires") {
                    TextField("Ouverture (HH:MM)", text: $open).keyboardType(.numbersAndPunctuation)
                    TextField("Fermeture (HH:MM)", text: $close).keyboardType(.numbersAndPunctuation)
                }
            }
            .navigationTitle(park.wName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save).disabled(dayKey.isEmpty) }
            }
            .onAppear {
                if dayKey.isEmpty { dayKey = trip.dayKeys.first ?? "" }
            }
        }
    }

    private func save() {
        let date = DayKey.date(fromKey: dayKey)
        let crowd: CrowdOverride
        if let existing = (park.crowdOverrides?.allObjects as? [CrowdOverride] ?? []).first(where: { $0.date.map { DayKey.key($0) } == dayKey }) {
            crowd = existing
        } else {
            crowd = context.make(CrowdOverride.self, trip: trip)
            crowd.park = park
            crowd.trip = trip
            crowd.date = date
        }
        crowd.level = Int16(level)
        crowd.label = CrowdScale.label(for: level)
        let hours: ParkHoursOverride
        if let existing = (park.hoursOverrides?.allObjects as? [ParkHoursOverride] ?? []).first(where: { $0.date.map { DayKey.key($0) } == dayKey }) {
            hours = existing
        } else {
            hours = context.make(ParkHoursOverride.self, trip: trip)
            hours.park = park
            hours.trip = trip
            hours.date = date
        }
        hours.openTime = open
        hours.closeTime = close
        context.saveIfNeeded()
        dismiss()
    }
}
