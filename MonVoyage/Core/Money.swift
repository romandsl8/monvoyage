import Foundation

/// Conversion de devises. Les taux sont exprimés en « EUR pour 1 unité de devise ».
enum Money {
    static func round2(_ value: Double) -> Double {
        (value * 100).rounded(.toNearestOrAwayFromZero) / 100
    }

    /// Convertit un montant vers l'EUR.
    static func toEUR(_ amount: Double, currency: String, rateEURPerUnit: Double) -> Double {
        if currency.uppercased() == "EUR" { return round2(amount) }
        return round2(amount * rateEURPerUnit)
    }

    /// Convertit un montant EUR vers la devise.
    static func fromEUR(_ amountEUR: Double, currency: String, rateEURPerUnit: Double) -> Double {
        if currency.uppercased() == "EUR" || rateEURPerUnit <= 0 { return round2(amountEUR) }
        return round2(amountEUR / rateEURPerUnit)
    }

    /// Lit un montant saisi à la française ou à l'américaine : « 1 234,56 », « 1,234.56 », « 12.5 ».
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            if c > d {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if let c = lastComma {
            let decimals = s.distance(from: c, to: s.endIndex) - 1
            if decimals == 3 && s.filter({ $0 == "," }).count >= 1 && !s.hasPrefix("0,") && s.count > 4 {
                s = s.replacingOccurrences(of: ",", with: "")
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        }
        return Double(s)
    }
}

/// Calculateur taxes + pourboire (prix affichés hors taxe aux États-Unis).
struct TaxTipResult: Equatable {
    var subtotal: Double
    var tax: Double
    var tip: Double
    var total: Double
    var totalEUR: Double
}

enum TaxTipCalculator {
    static let tipChoices: [Double] = [0, 0.15, 0.18, 0.20, 0.22]

    /// Le pourboire est calculé sur le prix hors taxe (usage courant aux États-Unis).
    static func compute(subtotal: Double, taxRate: Double, tipRate: Double, rateEURPerUnit: Double) -> TaxTipResult {
        let tax = Money.round2(subtotal * taxRate)
        let tip = Money.round2(subtotal * tipRate)
        let total = Money.round2(subtotal + tax + tip)
        return TaxTipResult(subtotal: subtotal, tax: tax, tip: tip, total: total,
                            totalEUR: Money.round2(total * rateEURPerUnit))
    }
}
