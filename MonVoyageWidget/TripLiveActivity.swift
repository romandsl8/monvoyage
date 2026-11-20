import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Live Activity / Dynamic Island : jour de vol (compte à rebours, terminal, siège) ou jour de parc.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color(hex: context.attributes.accentHex).opacity(0.25))
                .activitySystemActionForegroundColor(Color(hex: context.attributes.accentHex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.kind == "flight" ? "Vol" : "Parc",
                          systemImage: context.state.kind == "flight" ? "airplane" : "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: context.attributes.accentHex))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(Date(), context.state.targetDate), countsDown: true)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text([context.state.subtitle, context.state.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.kind == "flight" ? "airplane" : "sparkles")
                    .foregroundStyle(Color(hex: context.attributes.accentHex))
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date(), context.state.targetDate), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.kind == "flight" ? "airplane" : "sparkles")
                    .foregroundStyle(Color(hex: context.attributes.accentHex))
            }
        }
    }
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.kind == "flight" ? "airplane.departure" : "sparkles")
                .font(.title)
                .foregroundStyle(Color(hex: context.attributes.accentHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.title).font(.headline).lineLimit(1)
                Text(context.state.subtitle).font(.subheadline)
                if !context.state.detail.isEmpty {
                    Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(timerInterval: Date()...max(Date(), context.state.targetDate), countsDown: true)
                    .font(.title2.monospacedDigit().weight(.bold))
                    .multilineTextAlignment(.trailing)
                Text(context.attributes.tripName).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// Contrôle du Centre de contrôle / bouton Action : ajout express d'une dépense.
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickAddExpenseControl") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Dépense", systemImage: "eurosign.circle.fill")
            }
        }
        .displayName("Ajouter une dépense")
        .description("Ouvre MonVoyage sur l'ajout express d'une dépense.")
    }
}
