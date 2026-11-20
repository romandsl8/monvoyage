import Foundation

/// Résultat de l'analyse d'un ticket (proposé à l'utilisateur, qui valide ou corrige).
struct ParsedReceipt: Equatable {
    var total: Double?
    var date: Date?
    var merchant: String?
    var currency: String?
}

/// Analyse le texte reconnu (lignes de haut en bas) d'un ticket de caisse.
enum ReceiptParser {
    /// Mots-clés du total, du plus fiable au moins fiable.
    static let totalKeywords: [String] = [
        "GRAND TOTAL", "AMOUNT DUE", "BALANCE DUE", "TOTAL DUE", "TOTAL TTC", "NET A PAYER", "NET À PAYER",
        "MONTANT DU", "MONTANT DÛ", "A PAYER", "À PAYER", "BALANCE", "TOTAL"
    ]
    static let excludedKeywords: [String] = ["SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "SOUS-TOTAL", "SOUS TOTAL", "TAX", "TVA", "TIP", "GRATUITY", "POURBOIRE", "CHANGE", "RENDU", "SAVINGS"]

    static func parse(lines rawLines: [String]) -> ParsedReceipt {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var result = ParsedReceipt()
        result.total = findTotal(lines)
        result.date = findDate(lines)
        result.merchant = findMerchant(lines)
        let joined = lines.joined(separator: " ")
        if joined.contains("€") || joined.uppercased().contains("EUR") { result.currency = "EUR" }
        else if joined.contains("$") || joined.uppercased().contains("USD") { result.currency = "USD" }
        return result
    }

    static func findTotal(_ lines: [String]) -> Double? {
        for keyword in totalKeywords {
            for (index, line) in lines.enumerated() {
                let upper = line.uppercased()
                guard upper.contains(keyword) else { continue }
                if excludedKeywords.contains(where: { upper.contains($0) }) && !upper.contains("GRAND TOTAL") && !upper.contains("TOTAL DUE") && !upper.contains("AMOUNT DUE") {
                    continue
                }
                if let amount = amounts(in: line).last { return amount }
                if index + 1 < lines.count, let amount = amounts(in: lines[index + 1]).first { return amount }
            }
        }
        // Repli : le plus grand montant du ticket.
        return lines.flatMap { amounts(in: $0) }.max()
    }

    /// Montants avec décimales trouvés dans une ligne (« $12.50 », « 1 234,56 € »).
    static func amounts(in line: String) -> [Double] {
        let pattern = #"(?<![\d])(\d{1,3}(?:[ ,. ]\d{3})*[.,]\d{2}|\d+[.,]\d{2})(?![\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: line) else { return nil }
            return Money.parse(String(line[r]))
        }
    }

    static func findDate(_ lines: [String]) -> Date? {
        let patterns: [(String, (Int, Int, Int) -> DateComponents)] = [
            (#"(\d{4})-(\d{1,2})-(\d{1,2})"#, { a, b, c in DateComponents(year: a, month: b, day: c) }),
            (#"(\d{1,2})/(\d{1,2})/(\d{2,4})"#, { a, b, c in
                let year = c < 100 ? 2000 + c : c
                // Format US (MM/JJ) si le 1er nombre ≤ 12 et le 2e > 12, ou par défaut sur un ticket en $.
                if a > 12 { return DateComponents(year: year, month: b, day: a) }
                return DateComponents(year: year, month: a, day: b)
            }),
            (#"(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#, { a, b, c in DateComponents(year: c < 100 ? 2000 + c : c, month: b, day: a) })
        ]
        let cal = DayKey.calendar()
        for line in lines {
            for (pattern, build) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r1 = Range(m.range(at: 1), in: line), let r2 = Range(m.range(at: 2), in: line),
                      let r3 = Range(m.range(at: 3), in: line),
                      let a = Int(line[r1]), let b = Int(line[r2]), let c = Int(line[r3]) else { continue }
                var comps = build(a, b, c)
                comps.hour = 12
                if let month = comps.month, let day = comps.day, (1...12).contains(month), (1...31).contains(day),
                   let date = cal.date(from: comps) {
                    return date
                }
            }
        }
        return nil
    }

    static func findMerchant(_ lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let letters = line.filter { $0.isLetter }
            guard letters.count >= 3 else { continue }
            let upper = line.uppercased()
            if totalKeywords.contains(where: { upper.contains($0) }) { continue }
            if upper.contains("WELCOME") || upper.contains("BIENVENUE") || upper.contains("RECEIPT") || upper.contains("TICKET") { continue }
            if !amounts(in: line).isEmpty { continue }
            return line.capitalized
        }
        return nil
    }
}
