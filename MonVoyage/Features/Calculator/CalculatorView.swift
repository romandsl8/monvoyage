import SwiftUI

/// Calculateur taxes et pourboire (prix affiché hors taxe en USD).
struct CalculatorView: View {
    @ObservedObject var trip: Trip
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var nav: TripNavigation

    @SceneStorage("calc.price") private var priceText = ""
    @SceneStorage("calc.tip") private var tipRate = -1.0
    @SceneStorage("calc.customTip") private var customTipText = ""
    @SceneStorage("calc.custom") private var useCustomTip = false
    @State private var taxText = ""

    private var price: Double { Money.parse(priceText) ?? 0 }
    private var taxRate: Double { (Money.parse(taxText) ?? trip.taxRate * 100) / 100 }
    private var effectiveTip: Double {
        if useCustomTip { return (Money.parse(customTipText) ?? 0) / 100 }
        return tipRate >= 0 ? tipRate : trip.defaultTipRate
    }
    private var result: TaxTipResult {
        TaxTipCalculator.compute(subtotal: price, taxRate: taxRate, tipRate: effectiveTip, rateEURPerUnit: rates.usdToEUR)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    CardTitle(title: "Prix affiché (hors taxe)", symbol: "tag.fill", tint: trip.accent)
                    HStack(alignment: .firstTextBaseline) {
                        Text("$").font(.largeTitle.bold()).foregroundStyle(.secondary)
                        TextField("0,00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .accessibilityLabel("Prix hors taxe en dollars")
                    }
                    HStack {
                        Text("Taxe")
                        Spacer()
                        TextField(Fmt.number(trip.taxRate * 100, digits: 3), text: $taxText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                Card {
                    CardTitle(title: "Pourboire", symbol: "hand.thumbsup.fill", tint: trip.accent)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(TaxTipCalculator.tipChoices, id: \.self) { choice in
                                let selected = !useCustomTip && abs(effectiveTip - choice) < 0.0001
                                if selected {
                                    Button(Fmt.percent(choice)) { useCustomTip = false; tipRate = choice }
                                        .buttonStyle(.glassProminent)
                                        .accessibilityAddTraits(.isSelected)
                                } else {
                                    Button(Fmt.percent(choice)) { useCustomTip = false; tipRate = choice }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                    Toggle("Pourboire libre", isOn: $useCustomTip)
                    if useCustomTip {
                        HStack {
                            TextField("Pourcentage", text: $customTipText).keyboardType(.decimalPad)
                            Text("%")
                        }
                    }
                }
                Card {
                    CardTitle(title: "À payer", symbol: "equal.circle.fill", tint: trip.accent)
                    LabeledContent("Prix", value: Fmt.usd(result.subtotal))
                    LabeledContent("Taxe (\(Fmt.percent(taxRate)))", value: Fmt.usd(result.tax))
                    LabeledContent("Pourboire (\(Fmt.percent(effectiveTip)))", value: Fmt.usd(result.tip))
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        BigNumber(label: "Total", value: Fmt.usd(result.total), tint: trip.accent)
                        Spacer()
                        BigNumber(label: "En euros", value: Fmt.eur(result.totalEUR))
                    }
                    Text("1 $ = \(Fmt.number(rates.usdToEUR, digits: 4)) € · \(rates.isManual ? "taux manuel" : Fmt.updated(rates.updatedAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button {
                        nav.present(.newExpense(ExpensePrefill(title: "", amount: result.total, currency: "USD", categoryName: "Repas",
                                                               isPretax: true, tax: result.tax, tip: result.tip)))
                    } label: {
                        Label("Ajouter comme dépense", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(price <= 0)
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .groupedBackground()
        .navigationTitle("Taxes et pourboire")
        .scrollDismissesKeyboard(.interactively)
    }
}
