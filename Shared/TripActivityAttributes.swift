import Foundation
import ActivityKit

/// Live Activity / Dynamic Island : jour de vol ou jour de parc.
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "flight" ou "park"
        var kind: String
        var title: String
        var subtitle: String
        var targetDate: Date
        var detail: String
    }

    var tripName: String
    var accentHex: String
}
