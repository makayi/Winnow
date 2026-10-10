import Foundation

/// One verified file copy, stored in the card's JSON.
struct ImportRecord: Codable, Hashable, Sendable {
    var photoID: String
    var basename: String
    var fileName: String
    var size: Int64
    var sha256: String
    var destinationPath: String
    var date: Date
}
