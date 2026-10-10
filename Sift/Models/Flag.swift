import Foundation

enum Flag: String, Codable, Sendable, CaseIterable {
    case none, pick, reject

    /// Click on a thumbnail cycles none → pick → reject → none.
    var cycled: Flag {
        switch self {
        case .none: .pick
        case .pick: .reject
        case .reject: .none
        }
    }

    var accessibilityName: String {
        switch self {
        case .none: "Not flagged"
        case .pick: "Picked"
        case .reject: "Rejected"
        }
    }
}
