import SwiftUI
import UIKit

extension Color {
    /// Crée une couleur depuis "#RRGGBB" (repli : bleu).
    init(hex: String?) {
        var s = (hex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&value) else {
            self = Color(red: 0.23, green: 0.48, blue: 1.0)
            return
        }
        self = Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// Palette proposée pour la couleur d'accent d'un voyage.
enum AccentPalette {
    static let colors: [String] = ["#3A7BFF", "#5856D6", "#AF52DE", "#FF2D55", "#FF9500", "#34C759", "#00C7BE", "#30B0C7", "#A2845E"]
}

/// Couleurs de statut (budget / affluence).
enum StatusColor {
    static func budget(_ status: Int) -> Color {
        switch status {
        case 0: return .green
        case 1: return .orange
        default: return .red
        }
    }
}
