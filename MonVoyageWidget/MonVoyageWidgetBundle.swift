import WidgetKit
import SwiftUI

@main
struct MonVoyageWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        DailyBudgetWidget()
        NextActivityWidget()
        QuickAddControl()
    }
}

// MARK: - Timeline commune

struct TripEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry {
        TripEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        completion(TripEntry(date: Date(), snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .placeholder) : WidgetSnapshot.load()))
    }

    /// Une entrée maintenant puis une à chaque minuit (le compte à rebours change de jour).
    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        var entries = [TripEntry(date: Date(), snapshot: snapshot)]
        var day = calendar.startOfDay(for: Date())
        for _ in 0..<7 {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            entries.append(TripEntry(date: day, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Éléments visuels

struct WidgetGlyph: View {
    var size: CGFloat = 18
    var body: some View {
        Image("Glyph")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetGlyph(size: 22)
            Text("Aucun voyage").font(.headline)
            Text("Créez un voyage dans MonVoyage.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension WidgetSnapshot {
    func daysLeft(at date: Date) -> Int { DayMath.daysBetween(date, countdownTarget) }
    func isOngoing(at date: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: date)
        return Calendar.current.startOfDay(for: startDate) <= today && today <= Calendar.current.startOfDay(for: endDate)
    }
}

extension View {
    /// Fond discret : neutre avec un très léger voile de la couleur du voyage.
    /// En mode « Transparent » ou « Teinté » de l'écran d'accueil, le système le retire (verre).
    func tripWidgetBackground(_ hex: String?) -> some View {
        containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.background)
                LinearGradient(colors: [Color(hex: hex).opacity(0.10), Color(hex: hex).opacity(0.02)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}
