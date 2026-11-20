import Foundation

/// Résumé du voyage en cours (ou à venir) écrit par l'appli pour le widget.
struct WidgetSnapshot: Codable, Equatable {
    var tripName: String
    var city: String
    var accentHex: String
    var startDate: Date
    var endDate: Date
    var firstDeparture: Date?
    var dailyBudgetEUR: Double?
    var dailyBudgetUSD: Double?
    var spentTodayEUR: Double
    /// 0 = vert, 1 = orange, 2 = rouge
    var budgetStatus: Int
    var nextActivityTitle: String?
    var nextActivityDate: Date?
    var updatedAt: Date

    /// Date visée par le compte à rebours : premier décollage, sinon début du voyage.
    var countdownTarget: Date { firstDeparture ?? startDate }

    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent(SharedKeys.widgetSnapshotFile)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static let placeholder = WidgetSnapshot(
        tripName: "Floride", city: "Orlando", accentHex: "#3A7BFF",
        startDate: Date().addingTimeInterval(86400 * 42), endDate: Date().addingTimeInterval(86400 * 56),
        firstDeparture: nil, dailyBudgetEUR: 145, dailyBudgetUSD: 160, spentTodayEUR: 40, budgetStatus: 0,
        nextActivityTitle: "Islands of Adventure", nextActivityDate: Date().addingTimeInterval(3600),
        updatedAt: Date())
}
