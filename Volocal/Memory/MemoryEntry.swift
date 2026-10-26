import Foundation

/// One durable fact about the user. `key` is the slot that later statements update
/// instead of appending a second copy. `category` is the kind of fact.
struct MemoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var category: String
    var key: String
    var updatedAt: Date
}

/// A fact the extractor found in one user turn, before it is stored.
struct MemoryDraft: Equatable, Sendable {
    var category: String
    var key: String
    var text: String
}

enum MemoryCategory {
    static let name = "name"
    static let person = "person"
    static let pet = "pet"
    static let home = "home"
    static let job = "job"
    static let project = "project"
    static let preference = "preference"
    static let limit = "limit"
    static let language = "language"
    static let age = "age"
    static let gender = "gender"
}
