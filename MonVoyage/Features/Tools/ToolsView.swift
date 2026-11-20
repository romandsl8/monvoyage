import SwiftUI

/// Outils hors ligne : double horloge, conversions, tailles, Live Activity.
struct ToolsView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var conversion: UnitConversion = .temperature
    @State private var inputText = ""
    @State private var reversed = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: sizeClass == .regular ? [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)] : [GridItem(.flexible())],
                      spacing: 16) {
                clocks
                converter
                sizes
            }
            .padding()
        }
        .groupedBackground()
        .navigationTitle("Outils")
    }

    private var clocks: some View {
        Card {
            CardTitle(title: "Double horloge", symbol: "clock.fill", tint: trip.accent)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    clock("Paris", zone: TimeZone(identifier: "Europe/Paris") ?? .current, date: context.date)
                    Spacer()
                    clock(trip.city ?? "Sur place", zone: trip.tripTimeZone, date: context.date)
                }
            }
            let offset = FlightTime.offsetHours(from: TimeZone(identifier: "Europe/Paris") ?? .current, to: trip.tripTimeZone, at: Date())
            Text(offset == 0 ? "Même heure qu'à Paris" : "Décalage : \(offset > 0 ? "+" : "")\(Fmt.number(offset, digits: 1)) h par rapport à Paris")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func clock(_ label: String, zone: TimeZone, date: Date) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.time(date, timeZone: zone)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
            Text(Fmt.day(date, timeZone: zone)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var converter: some View {
        Card {
            CardTitle(title: "Conversions", symbol: "arrow.left.arrow.right", tint: trip.accent)
            Picker("Conversion", selection: $conversion) {
                ForEach(UnitConversion.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            HStack {
                TextField("Valeur", text: $inputText).keyboardType(.numbersAndPunctuation)
                    .font(.title3.monospacedDigit())
                Text(reversed ? conversion.units.1 : conversion.units.0).foregroundStyle(.secondary)
                Button { reversed.toggle() } label: { Image(systemName: "arrow.left.arrow.right.circle.fill").font(.title2) }
                    .accessibilityLabel("Inverser")
            }
            if let value = Money.parse(inputText.replacingOccurrences(of: "−", with: "-")) {
                let result = conversion.convert(value, reversed: reversed)
                Text("= \(Fmt.number(result, digits: 2)) \(reversed ? conversion.units.0 : conversion.units.1)")
                    .font(.title2.bold()).fontDesign(.rounded).foregroundStyle(trip.accent)
            }
        }
    }

    private var sizes: some View {
        Card {
            CardTitle(title: "Tailles US ↔ FR", symbol: "tshirt.fill", tint: trip.accent)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Vêtements femme").bold(); Text("US"); Text("FR") }.font(.caption)
                ForEach(SizeTables.womenClothes, id: \.0) { row in
                    GridRow { Text(""); Text(row.0); Text(row.1) }.font(.caption.monospacedDigit())
                }
                Divider()
                GridRow { Text("Vêtements homme").bold(); Text("US"); Text("FR") }.font(.caption)
                ForEach(SizeTables.menClothes, id: \.0) { row in
                    GridRow { Text(""); Text(row.0); Text(row.1) }.font(.caption.monospacedDigit())
                }
                Divider()
                GridRow { Text("Chaussures femme").bold(); Text("US"); Text("FR") }.font(.caption)
                ForEach(SizeTables.womenShoes, id: \.0) { row in
                    GridRow { Text(""); Text(row.0); Text(row.1) }.font(.caption.monospacedDigit())
                }
                Divider()
                GridRow { Text("Chaussures homme").bold(); Text("US"); Text("FR") }.font(.caption)
                ForEach(SizeTables.menShoes, id: \.0) { row in
                    GridRow { Text(""); Text(row.0); Text(row.1) }.font(.caption.monospacedDigit())
                }
            }
        }
    }

}

/// Conversions d'unités hors ligne.
enum UnitConversion: String, CaseIterable, Identifiable {
    case temperature, distance, volume, weight, length

    var id: String { rawValue }
    var title: String {
        switch self {
        case .temperature: return "°F ↔ °C"
        case .distance: return "miles ↔ km"
        case .volume: return "gallons ↔ litres"
        case .weight: return "livres ↔ kg"
        case .length: return "pouces ↔ cm"
        }
    }
    var units: (String, String) {
        switch self {
        case .temperature: return ("°F", "°C")
        case .distance: return ("mi", "km")
        case .volume: return ("gal", "L")
        case .weight: return ("lb", "kg")
        case .length: return ("in", "cm")
        }
    }

    func convert(_ value: Double, reversed: Bool) -> Double {
        switch self {
        case .temperature: return reversed ? value * 9 / 5 + 32 : (value - 32) * 5 / 9
        case .distance: return reversed ? value / 1.609344 : value * 1.609344
        case .volume: return reversed ? value / 3.785411784 : value * 3.785411784
        case .weight: return reversed ? value / 0.45359237 : value * 0.45359237
        case .length: return reversed ? value / 2.54 : value * 2.54
        }
    }
}

enum SizeTables {
    static let womenClothes: [(String, String)] = [("2", "34"), ("4", "36"), ("6", "38"), ("8", "40"), ("10", "42"), ("12", "44"), ("14", "46")]
    static let menClothes: [(String, String)] = [("XS", "44"), ("S", "46"), ("M", "48-50"), ("L", "52"), ("XL", "54-56"), ("XXL", "58")]
    static let womenShoes: [(String, String)] = [("5", "35.5"), ("6", "36.5"), ("7", "37.5"), ("8", "38.5"), ("9", "40"), ("10", "41")]
    static let menShoes: [(String, String)] = [("7", "40"), ("8", "41"), ("9", "42"), ("10", "43"), ("11", "44.5"), ("12", "46")]
}
