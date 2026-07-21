import Foundation
import GRDB
import ArgumentParser

public enum TodoStatus: String, Codable, CaseIterable, Sendable, ExpressibleByArgument {
    case pending
    case scheduled
    case inProgress = "in_progress"
    case completed
    case dismissed
}

public enum Priority: String, Codable, CaseIterable, Sendable, ExpressibleByArgument {
    case high
    case medium
    case low
}

public enum TodoSource: String, Codable, Sendable, ExpressibleByArgument {
    case manual
    case calendar
    case aiSuggested = "ai_suggested"
}

public struct Todo: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var todoDescription: String?
    public var status: String
    public var priority: String?
    public var source: String
    public var parentEventId: String?
    public var parentTodoId: String?
    public var calendarId: String?
    public var dueDate: Date?
    public var scheduledDate: Date?
    public var completedAt: Date?
    public var sortOrder: Int
    public var aiReason: String?
    public var startMinute: Int?
    public var endMinute: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public static let databaseTableName = "todos"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case todoDescription = "description"
        case status
        case priority
        case source
        case parentEventId = "parent_event_id"
        case parentTodoId = "parent_todo_id"
        case calendarId = "calendar_id"
        case dueDate = "due_date"
        case scheduledDate = "scheduled_date"
        case completedAt = "completed_at"
        case sortOrder = "sort_order"
        case aiReason = "ai_reason"
        case startMinute = "start_minute"
        case endMinute = "end_minute"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        todoDescription: String? = nil,
        status: TodoStatus = .pending,
        priority: Priority? = nil,
        source: TodoSource = .manual,
        parentEventId: String? = nil,
        parentTodoId: String? = nil,
        calendarId: String? = nil,
        dueDate: Date? = nil,
        scheduledDate: Date? = nil,
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        aiReason: String? = nil,
        startMinute: Int? = nil,
        endMinute: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.todoDescription = todoDescription
        self.status = status.rawValue
        self.priority = priority?.rawValue
        self.source = source.rawValue
        self.parentEventId = parentEventId
        self.parentTodoId = parentTodoId
        self.calendarId = calendarId
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.aiReason = aiReason
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// "HH:mm–HH:mm", "HH:mm~", or nil when no time assigned.
    public var timeRangeLabel: String? {
        guard let start = DateHelpers.formatMinutes(startMinute) else { return nil }
        if let end = DateHelpers.formatMinutes(endMinute) {
            return "\(start)–\(end)"
        }
        return start
    }

    public var statusEnum: TodoStatus {
        get { TodoStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    public var priorityEnum: Priority? {
        get { priority.flatMap { Priority(rawValue: $0) } }
        set { priority = newValue?.rawValue }
    }

    public var sourceEnum: TodoSource {
        get { TodoSource(rawValue: source) ?? .manual }
        set { source = newValue.rawValue }
    }
}

public struct TodoWithCategories: Identifiable, Sendable {
    public var todo: Todo
    public var categories: [Category]

    public var id: String { todo.id }

    public init(todo: Todo, categories: [Category] = []) {
        self.todo = todo
        self.categories = categories
    }
}
