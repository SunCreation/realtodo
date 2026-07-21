import Foundation
import GRDB

public struct Category: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: String
    public var sortOrder: Int
    public var createdAt: Date

    public static let databaseTableName = "categories"

    public init(id: String = UUID().uuidString, name: String, color: String, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
