import SwiftUI

// MARK: - Charte graphique
//
// - Fond : gris groupé du système + léger halo de la couleur du voyage en haut d'écran.
// - Cartes : coins très arrondis (24), ombre douce, en-tête « pastille d'icône + titre ».
// - Chiffres clés en police arrondie, grands ; libellés courts en gris.
// - Couleurs d'état constantes : vert = ok / payé, orange = attention, rouge = retard / dépassement.

enum Theme {
    static let cardRadius: CGFloat = 24
    static let heroRadius: CGFloat = 28
    static let spacing: CGFloat = 16
}

/// Carte sans bordure, ombre douce.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

/// Pastille ronde teintée contenant un symbole.
struct IconBubble: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}

/// En-tête de carte : pastille d'icône + titre.
struct CardTitle: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            IconBubble(symbol: symbol, tint: tint, size: 30)
            Text(title)
                .font(.headline)
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Grande carte d'en-tête en dégradé de la couleur du voyage (texte blanc).
struct HeroCard<Content: View>: View {
    let tint: Color
    /// Parc dont la photo sert de fond (sinon dégradé).
    var park: Park? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(20)
            .padding(.top, park != nil ? 40 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(park != nil ? 0.35 : 0), radius: 4)
            .background {
                ParkPhotoBackground(park: park, tint: tint)
                    .clipShape(.rect(cornerRadius: Theme.heroRadius, style: .continuous))
            }
            .shadow(color: tint.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

/// Petite statistique : libellé, valeur, pastille.
struct StatTile: View {
    let label: String
    let value: String
    var symbol: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let symbol { IconBubble(symbol: symbol, tint: tint, size: 28) }
            Text(value)
                .font(.title3.bold()).fontDesign(.rounded).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Jauge circulaire (pourcentage au centre).
struct RingGauge: View {
    let fraction: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 10
    var label: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(fraction > 1 ? Color.red : tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label ?? Fmt.percent(min(fraction, 9.99)))
                .font(.caption.bold()).fontDesign(.rounded).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(lineWidth)
        }
        .accessibilityElement()
        .accessibilityLabel("Progression")
        .accessibilityValue(Fmt.percent(fraction))
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
                    .frame(width: max(8, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 10)
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
        background {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                // Halo de la couleur du voyage (teinte courante) en haut de l'écran.
                Rectangle()
                    .fill(.tint)
                    .opacity(0.14)
                    .frame(height: 320)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
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

/// Heure locale de la destination, mise à jour chaque minute, avec le décalage par rapport à l'iPhone.
struct LocalTimeLabel: View {
    let timeZone: TimeZone
    var place: String? = nil

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            Label {
                Text(text(now))
            } icon: {
                Image(systemName: "clock.fill")
            }
            .accessibilityLabel("Heure locale \(text(now))")
        }
    }

    private func text(_ now: Date) -> String {
        var parts = [Self.time(now, timeZone)]
        if let place, !place.isEmpty { parts[0] += " à \(place)" }
        let diff = (timeZone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 60
        if diff != 0 {
            let h = abs(diff) / 60, m = abs(diff) % 60
            parts.append("\(diff > 0 ? "+" : "−")\(h) h\(m > 0 ? String(format: "%02d", m) : "") par rapport à vous")
        }
        return parts.joined(separator: " · ")
    }

    static func time(_ date: Date, _ timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%dh%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
