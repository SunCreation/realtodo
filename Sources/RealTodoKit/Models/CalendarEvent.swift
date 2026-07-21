import Foundation
import GRDB

public struct CalendarEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: String
    public var calendarId: String
    public var calendarName: String?
    public var title: String?
    public var startTime: Date?
    public var endTime: Date?
    public var description: String?
    public var syncedAt: Date?

    public static let databaseTableName = "calendar_events"

    enum CodingKeys: String, CodingKey {
        case id
        case calendarId = "calendar_id"
        case calendarName = "calendar_name"
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case description
        case syncedAt = "synced_at"
    }

    public init(
        id: String,
        calendarId: String,
        calendarName: String? = nil,
        title: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        description: String? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.calendarId = calendarId
        self.calendarName = calendarName
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.description = description
        self.syncedAt = syncedAt
    }
}

public struct CalendarMapping: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var accountId: String?
    public var calendarId: String
    public var calendarName: String
    public var categoryId: String

    public static let databaseTableName = "calendar_mappings"

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case calendarId = "calendar_id"
        case calendarName = "calendar_name"
        case categoryId = "category_id"
    }

    public init(accountId: String? = nil, calendarId: String, calendarName: String, categoryId: String) {
        self.accountId = accountId
        self.calendarId = calendarId
        self.calendarName = calendarName
        self.categoryId = categoryId
    }
}
