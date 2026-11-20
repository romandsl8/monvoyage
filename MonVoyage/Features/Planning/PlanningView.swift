import SwiftUI
import CoreData

/// Planning jour par jour (généré à partir des dates du voyage).
struct PlanningView: View {
    @ObservedObject var trip: Trip
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var nav: TripNavigation
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var affluence: AffluenceService

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if trip.days.isEmpty {
                    EmptyState(symbol: "calendar", title: "Dates à définir", message: "Renseignez les dates du voyage pour générer le planning.",
                               actionTitle: "Modifier le voyage") { nav.present(.editTrip) }
                        .padding(.top, 60)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(trip.dayKeys, id: \.self) { key in
                        DayCard(trip: trip, dayKey: key).id(key)
                    }
                }
                .padding()
            }
            .groupedBackground()
            .onAppear {
                let today = DayKey.key(Date())
                if trip.dayKeys.contains(today) { proxy.scrollTo(today, anchor: .top) }
            }
        }
        .navigationTitle("Planning")
        .refreshable { await refresh(force: true) }
        .task { await refresh(force: false) }
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)] : [GridItem(.flexible())]
    }

    private func refresh(force: Bool) async {
        guard let id = trip.id?.uuidString else { return }
        await weather.refresh(tripKey: id, latitude: trip.latitude, longitude: trip.longitude, dayKeys: trip.dayKeys, force: force)
        await affluence.refresh(force: force)
    }
}

/// Carte d'un jour : météo, affluence, vols, activités.
struct DayCard: View {
    @ObservedObject var trip: Trip
    let dayKey: String
    @EnvironmentObject private var nav: TripNavigation

    var body: some View {
        let date = DayKey.date(fromKey: dayKey) ?? Date()
        let isToday = dayKey == DayKey.key(Date())
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.longDay(date).capitalized).font(.headline).fontDesign(.rounded)
                    if let index = trip.dayKeys.firstIndex(of: dayKey) {
                        Text("Jour \(index + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isToday { GlassChip(text: "Aujourd'hui", symbol: "sun.max.fill", tint: trip.accent) }
            }
            DayHeaderInfo(trip: trip, dayKey: dayKey)
            ForEach(trip.flights(on: dayKey), id: \.objectID) { segment in
                FlightLine(segment: segment)
            }
            ForEach(trip.activities(on: dayKey), id: \.objectID) { activity in
                Button { nav.present(.editActivity(activity.objectID)) } label: {
                    ActivityLine(activity: activity, timeZone: trip.tripTimeZone)
                }
                .buttonStyle(.plain)
            }
            Button { nav.present(.newActivity(dayKey)) } label: {
                Label("Ajouter une activité", systemImage: "plus").font(.subheadline)
            }
            .buttonStyle(.glass)
        }
        .overlay {
            if isToday { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(trip.accent, lineWidth: 2) }
        }
    }
}

/// Météo + affluence et horaires (jour de parc), avec source et date de mise à jour.
struct DayHeaderInfo: View {
    @ObservedObject var trip: Trip
    let dayKey: String
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var affluence: AffluenceService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let id = trip.id?.uuidString, let w = weather.weather(tripKey: id, dayKey: dayKey) {
                WeatherBadge(weather: w, updatedAt: weather.updatedAt(tripKey: id))
            }
            ForEach(trip.parks(on: dayKey), id: \.objectID) { park in
                CrowdBadge(park: park, info: affluence.info(park: park, dayKey: dayKey))
            }
        }
    }
}

struct WeatherBadge: View {
    let weather: DayWeather
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Fmt.temp(weather.tMin)) / \(Fmt.temp(weather.tMax)) · \(weather.label)")
                    .font(.subheadline.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if weather.precipitation > 0.1 { parts.append("pluie \(Fmt.number(weather.precipitation, digits: 1)) mm") }
        if let p = weather.precipitationProbability { parts.append("\(p) %") }
        parts.append(weather.isNormal ? "normale (année précédente)" : "prévision")
        parts.append(Fmt.updated(updatedAt))
        return parts.joined(separator: " · ")
    }
}

struct CrowdBadge: View {
    let park: Park
    let info: CrowdInfo?

    var body: some View {
        HStack(spacing: 10) {
            if let level = info?.level {
                Text("\(level)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 34, height: 34)
                    .background(CrowdColor.color(for: level).opacity(0.25), in: .circle)
                    .overlay(Circle().stroke(CrowdColor.color(for: level), lineWidth: 2))
                    .accessibilityLabel("Affluence \(level) sur 10")
            } else {
                Image(systemName: "person.3").frame(width: 34, height: 34).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(park.wName)\(info?.label.map { " · \($0)" } ?? "")").font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let info else { return "Affluence inconnue · saisie manuelle dans Parcs" }
        var parts: [String] = []
        if let open = info.open, let close = info.close { parts.append("\(open)–\(close)") }
        if !info.source.isEmpty { parts.append(info.source) }
        parts.append(Fmt.updated(info.updatedAt))
        return parts.joined(separator: " · ")
    }
}

struct FlightLine: View {
    @ObservedObject var segment: FlightSegment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane").foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(segment.flightNumber ?? "Vol") · \(segment.routeText)").font(.subheadline.weight(.semibold))
                if let dep = segment.departureDate, let arr = segment.arrivalDate {
                    Text("\(Fmt.time(dep, timeZone: segment.departureZone)) → \(Fmt.time(arr, timeZone: segment.arrivalZone)) (heures locales) · \(segment.durationText ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ActivityLine: View {
    @ObservedObject var activity: PlanActivity
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 10) {
            Text(activity.time.map { Fmt.time($0, timeZone: timeZone) } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Image(systemName: activity.kind.symbol).foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.wTitle).font(.subheadline)
                if let place = activity.place, !place.isEmpty { Text(place).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if activity.cost > 0 { Text(Fmt.eurShort(activity.cost)).font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
