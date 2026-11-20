import WidgetKit
import SwiftUI

// MARK: - Compte à rebours (accueil + écran verrouillé)

struct CountdownWidget: Widget {
    let kind = "CountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TripProvider()) { entry in
            CountdownView(entry: entry)
        }
        .configurationDisplayName("Compte à rebours")
        .description("Jours restants avant le départ.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CountdownView: View {
    let entry: TripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .accessoryCircular: circular(s)
                case .accessoryRectangular: rectangular(s)
                case .accessoryInline: inline(s)
                case .systemMedium: medium(s)
                default: small(s)
                }
            } else {
                EmptyWidgetView()
            }
        }
        .tripWidgetBackground(entry.snapshot?.accentHex)
        .widgetURL(URL(string: "monvoyage://open"))
    }

    private func headline(_ s: WidgetSnapshot) -> (big: String, small: String) {
        if s.isOngoing(at: entry.date) {
            let day = DayMath.daysBetween(s.startDate, entry.date) + 1
            return ("J\(day)", "du voyage")
        }
        let days = s.daysLeft(at: entry.date)
        if days < 0 { return ("✓", "terminé") }
        if days == 0 { return ("Jour J", "c'est aujourd'hui !") }
        return ("\(days)", days == 1 ? "jour" : "jours")
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        let h = headline(s)
        return VStack(alignment: .leading, spacing: 2) {
            HStack { WidgetGlyph(); Spacer() }
                .foregroundStyle(Color(hex: s.accentHex))
            Spacer()
            Text(h.big).font(.system(size: 44, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            Text(h.small).font(.caption).foregroundStyle(.secondary)
            Text(s.tripName).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        let h = headline(s)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                WidgetGlyph(size: 22).foregroundStyle(Color(hex: s.accentHex))
                Spacer()
                Text(h.big).font(.system(size: 48, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                Text(h.small).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(s.tripName).font(.headline).lineLimit(1)
                if !s.city.isEmpty { Label(s.city, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                Text("\(Fmt.day(s.startDate)) → \(Fmt.day(s.endDate))").font(.caption).foregroundStyle(.secondary)
                if let budget = s.dailyBudgetEUR {
                    Label("\(Fmt.eurShort(budget)) / jour", systemImage: "eurosign.circle").font(.caption)
                        .foregroundStyle(StatusColor.budget(s.budgetStatus))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func circular(_ s: WidgetSnapshot) -> some View {
        let h = headline(s)
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(h.big).font(.system(size: 20, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
                Text(s.isOngoing(at: entry.date) ? "jour" : "J-").font(.system(size: 9))
            }
        }
        .widgetAccentable()
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        let h = headline(s)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { WidgetGlyph(size: 12); Text(s.tripName).font(.headline).lineLimit(1) }
            Text("\(h.big) \(h.small)").font(.system(.body, design: .rounded).weight(.semibold))
            Text(Fmt.day(s.countdownTarget)).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: WidgetSnapshot) -> some View {
        let h = headline(s)
        return Text("\(s.tripName) : \(h.big) \(h.small)")
    }
}

// MARK: - Budget restant par jour

struct DailyBudgetWidget: Widget {
    let kind = "DailyBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TripProvider()) { entry in
            DailyBudgetView(entry: entry)
        }
        .configurationDisplayName("Budget du jour")
        .description("Budget restant par jour pendant le voyage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DailyBudgetView: View {
    let entry: TripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot, let eur = s.dailyBudgetEUR {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                        Text("Budget / jour").font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color(hex: s.accentHex))
                    Spacer()
                    Text(Fmt.eurShort(eur))
                        .font(.system(size: family == .systemMedium ? 40 : 32, weight: .bold, design: .rounded))
                        .foregroundStyle(StatusColor.budget(s.budgetStatus))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .widgetAccentable()
                    if let usd = s.dailyBudgetUSD { Text(Fmt.usd(usd)).font(.caption).foregroundStyle(.secondary) }
                    Text("Dépensé aujourd'hui : \(Fmt.eurShort(s.spentTodayEUR))").font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyWidgetView()
            }
        }
        .tripWidgetBackground(entry.snapshot?.accentHex)
    }
}

// MARK: - Prochaine activité

struct NextActivityWidget: Widget {
    let kind = "NextActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TripProvider()) { entry in
            NextActivityView(entry: entry)
        }
        .configurationDisplayName("Prochaine activité")
        .description("La prochaine étape de votre planning.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextActivityView: View {
    let entry: TripEntry

    var body: some View {
        Group {
            if let s = entry.snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        WidgetGlyph(size: 16)
                        Text("À suivre").font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color(hex: s.accentHex))
                    Spacer()
                    if let title = s.nextActivityTitle, let date = s.nextActivityDate, date > entry.date {
                        Text(title).font(.headline).lineLimit(2)
                        Text("\(Fmt.day(date)) · \(Fmt.time(date))").font(.caption).foregroundStyle(.secondary)
                        Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Rien de prévu").font(.headline)
                        Text(s.tripName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyWidgetView()
            }
        }
        .tripWidgetBackground(entry.snapshot?.accentHex)
    }
}
