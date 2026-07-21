import Foundation
import GRDB

public struct GoogleAccount: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: String
    public var email: String
    public var displayName: String?
    public var accessToken: String
    public var refreshToken: String?
    public var expirationDate: Date
    public var scope: String?
    public var createdAt: Date

    public static let databaseTableName = "google_accounts"

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expirationDate = "expiration_date"
        case scope
        case createdAt = "created_at"
    }

    public init(
        id: String,
        email: String,
        displayName: String? = nil,
        accessToken: String,
        refreshToken: String? = nil,
        expirationDate: Date,
        scope: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expirationDate = expirationDate
        self.scope = scope
        self.createdAt = createdAt
    }

    public var isExpired: Bool { Date() >= expirationDate }
}
