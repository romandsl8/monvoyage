import SwiftUI
import CoreData

/// Tableau des temps d'attente en direct de toutes les attractions des parcs du voyage,
/// mis à jour automatiquement toutes les minutes tant que l'écran est affiché.
struct WaitTimesBoard: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var queueTimes: QueueTimesService

    enum Sort: String, CaseIterable, Identifiable {
        case waitAsc, waitDesc, name, park
        var id: String { rawValue }
        var label: String {
            switch self {
            case .waitAsc: return "Attente la plus courte"
            case .waitDesc: return "Attente la plus longue"
            case .name: return "Nom"
            case .park: return "Parc"
            }
        }
    }

    @AppStorage("waits.sort") private var sortRaw = Sort.waitAsc.rawValue
    @AppStorage("waits.openOnly") private var openOnly = true
    @AppStorage("waits.myListOnly") private var myListOnly = false
    @State private var parkFilter: Int64? = nil
    @State private var search = ""
    @State private var refreshing = false
    @State private var addedTick = 0
    @State private var showPicker = false

    static let refreshSeconds: UInt64 = 60

    private var sort: Sort { Sort(rawValue: sortRaw) ?? .waitAsc }
    private var parks: [Park] { trip.parkList.filter { $0.queueTimesID > 0 } }

    private func parkName(_ id: Int64) -> String {
        parks.first { $0.queueTimesID == id }?.wName ?? "Parc"
    }

    /// Attractions de « Ma liste » (par id Queue-Times).
    private var myListIDs: Set<Int64> {
        Set(parks.flatMap { $0.attractionList.map(\.queueTimesID) }.filter { $0 > 0 })
    }

    private var allRides: [LiveRide] {
        parks.flatMap { queueTimes.liveRides[$0.queueTimesID]?.rides ?? queueTimes.cachedLive(parkID: $0.queueTimesID)?.rides ?? [] }
    }

    private var rides: [LiveRide] {
        let mine = myListIDs
        let q = search.trimmingCharacters(in: .whitespaces)
        var list = allRides.filter { ride in
            (parkFilter == nil || ride.parkID == parkFilter)
            && (!openOnly || ride.isOpen)
            && (!myListOnly || mine.contains(ride.id))
            && (q.isEmpty || ride.name.localizedCaseInsensitiveContains(q) || ride.land.localizedCaseInsensitiveContains(q))
        }
        switch sort {
        case .waitAsc:
            list.sort { ($0.isOpen ? $0.wait : Int.max, $0.name) < ($1.isOpen ? $1.wait : Int.max, $1.name) }
        case .waitDesc:
            list.sort { ($0.isOpen ? $0.wait : -1, $1.name) > ($1.isOpen ? $1.wait : -1, $0.name) }
        case .name:
            list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .park:
            list.sort { (parkName($0.parkID), $0.land, $0.name) < (parkName($1.parkID), $1.land, $1.name) }
        }
        return list
    }

    private var lastUpdate: Date? {
        parks.compactMap { queueTimes.liveRides[$0.queueTimesID]?.updatedAt ?? queueTimes.cachedLive(parkID: $0.queueTimesID)?.updatedAt }.min()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                filters
                statusLine
                if parks.isEmpty {
                    EmptyState(symbol: "sparkles", title: "Aucun parc",
                               message: "Choisissez les parcs de votre voyage pour voir leurs temps d'attente en direct.",
                               actionTitle: "Choisir les parcs") { showPicker = true }
                } else if rides.isEmpty {
                    EmptyState(symbol: "clock.badge.questionmark", title: allRides.isEmpty ? "Pas encore de données" : "Aucune attraction",
                               message: allRides.isEmpty
                                   ? "Les temps d'attente s'affichent dès que la connexion le permet."
                                   : (openOnly ? "Aucune attraction ouverte avec ces filtres (les parcs sont peut-être fermés)." : "Aucune attraction ne correspond aux filtres."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 300 : 280), spacing: 10)], spacing: 10) {
                        ForEach(rides) { ride in
                            RideTile(ride: ride, parkName: parkName(ride.parkID), showPark: parkFilter == nil,
                                     inMyList: myListIDs.contains(ride.id)) { add(ride) }
                        }
                    }
                }
                QueueTimesCredit().padding(.top, 8)
            }
            .padding()
        }
        .groupedBackground()
        .searchable(text: $search, prompt: "Rechercher une attraction")
        .refreshable { await refresh() }
        .sheet(isPresented: $showPicker) { ParkPickerView(trip: trip) }
        .task(id: parks.map(\.queueTimesID)) {
            // Temps réel : actualisation à l'ouverture puis toutes les minutes, tant que l'écran est visible.
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: Self.refreshSeconds * 1_000_000_000)
            }
        }
        .sensoryFeedback(.success, trigger: addedTick)
    }

    // MARK: Filtres

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tous les parcs", selected: parkFilter == nil) { parkFilter = nil }
                ForEach(parks, id: \.objectID) { park in
                    chip(park.wName, selected: parkFilter == park.queueTimesID) {
                        parkFilter = parkFilter == park.queueTimesID ? nil : park.queueTimesID
                    }
                }
                Divider().frame(height: 22)
                chip("Ouvertes", selected: openOnly, symbol: "checkmark.circle") { openOnly.toggle() }
                chip("Ma liste", selected: myListOnly, symbol: "star.fill") { myListOnly.toggle() }
                Menu {
                    Picker("Trier par", selection: $sortRaw) {
                        ForEach(Sort.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } label: {
                    Label(sort.label, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, selected: Bool, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? trip.accent : Color(.secondarySystemGroupedBackground), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green) }
            Text(lastUpdate.map { "En direct · \(Fmt.updated($0)) · actualisé toutes les minutes" } ?? "Chargement des temps d'attente…")
            Spacer()
            Text("\(rides.count) attraction\(rides.count > 1 ? "s" : "")")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Actions

    private func refresh() async {
        refreshing = true
        await queueTimes.refreshWaits(parkIDs: parks.map(\.queueTimesID))
        refreshing = false
    }

    /// Ajoute l'attraction à « Ma liste » du parc.
    private func add(_ ride: LiveRide) {
        guard !myListIDs.contains(ride.id), let park = parks.first(where: { $0.queueTimesID == ride.parkID }) else { return }
        let a = context.make(Attraction.self, trip: trip)
        a.name = ride.name
        a.area = ride.land
        a.queueTimesID = ride.id
        a.priority = AttractionPriority.ifPossible.rawValue
        a.sortIndex = Int32(park.attractionList.count)
        a.park = park
        context.saveIfNeeded()
        addedTick += 1
    }
}

/// Tuile d'une attraction : attente en grand, couleur selon l'attente.
struct RideTile: View {
    let ride: LiveRide
    let parkName: String
    let showPark: Bool
    let inMyList: Bool
    let onAdd: () -> Void

    private var color: Color {
        guard ride.isOpen else { return .secondary }
        switch ride.wait {
        case ..<20: return .green
        case 20..<45: return .yellow
        case 45..<75: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                if ride.isOpen {
                    Text("\(ride.wait)").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("min").font(.caption2.weight(.semibold))
                } else {
                    Image(systemName: "xmark.circle").font(.title3)
                    Text("Fermé").font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(ride.isOpen ? Color.white : Color.secondary)
            .frame(width: 62, height: 62)
            .background(ride.isOpen ? color : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(ride.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(showPark ? "\(parkName) · \(ride.land)" : ride.land)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onAdd) {
                Image(systemName: inMyList ? "star.fill" : "star")
                    .foregroundStyle(inMyList ? Color.yellow : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(inMyList)
            .accessibilityLabel(inMyList ? "Dans ma liste" : "Ajouter à ma liste")
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ride.name), \(parkName), \(ride.isOpen ? "\(ride.wait) minutes d'attente" : "fermée")")
    }
}
