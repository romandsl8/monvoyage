import SwiftUI

/// Carte sans bordure.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Titre de carte.
struct CardTitle: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }
}

/// Chiffre clé en grand.
struct BigNumber: View {
    let label: String
    let value: String
    var tint: Color = .primary
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .fontDesign(.rounded)
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Jauge horizontale simple.
struct ProgressBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(fraction > 1 ? Color.red : tint)
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Progression")
        .accessibilityValue(Fmt.percent(fraction))
    }
}

/// État vide soigné avec action.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glassProminent)
            }
        }
    }
}

/// Bouton flottant « + » en verre.
struct FloatingAddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 30, height: 30)
                .padding(8)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .padding(20)
    }
}

/// Champ montant (saisie libre, virgule ou point).
struct AmountField: View {
    let title: String
    @Binding var text: String
    var currency: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0,00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 160)
                .accessibilityLabel(title)
            if let currency { Text(currency == "EUR" ? "€" : (currency == "USD" ? "$" : currency)).foregroundStyle(.secondary) }
        }
    }
}

/// Étiquette de mise à jour (source + date).
struct UpdatedLabel: View {
    let source: String
    let date: Date?

    var body: some View {
        Text("\(source) · \(Fmt.updated(date))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// Mention obligatoire Queue-Times.
struct QueueTimesCredit: View {
    var body: some View {
        Link(destination: APIEndpoints.queueTimesCredit) {
            Text("Powered by Queue-Times.com").font(.caption2).underline()
        }
        .foregroundStyle(.secondary)
    }
}

/// Bulle de verre teintée (chips).
struct GlassChip: View {
    let text: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
    }
}

extension View {
    /// Fond groupé standard pour les écrans en cartes.
    func groupedBackground() -> some View {
        background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

/// Couleurs d'affluence.
enum CrowdColor {
    static func color(for level: Int) -> Color {
        switch CrowdScale.colorIndex(for: level) {
        case 0: return .green
        case 1: return .mint
        case 2: return .yellow
        case 3: return .orange
        default: return .red
        }
    }
}
