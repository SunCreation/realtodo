import Foundation

public struct AISuggestion: Codable, Sendable {
    public var title: String
    public var categories: [String]
    public var parentEventId: String?
    public var parentTodoId: String?
    public var reason: String
    public var priority: String?
    public var subtasks: [AISubtask]?

    enum CodingKeys: String, CodingKey {
        case title, categories, reason, priority, subtasks
        case parentEventId = "parentEventId"
        case parentTodoId = "parentTodoId"
    }

    public init(
        title: String,
        categories: [String] = [],
        parentEventId: String? = nil,
        parentTodoId: String? = nil,
        reason: String = "",
        priority: String? = nil,
        subtasks: [AISubtask]? = nil
    ) {
        self.title = title
        self.categories = categories
        self.parentEventId = parentEventId
        self.parentTodoId = parentTodoId
        self.reason = reason
        self.priority = priority
        self.subtasks = subtasks
    }
}

public struct AISubtask: Codable, Sendable {
    public var title: String
    public var reason: String?

    public init(title: String, reason: String? = nil) {
        self.title = title
        self.reason = reason
    }
}

public struct AIBreakdownResponse: Codable, Sendable {
    public var tasks: [AISuggestion]
}

/// A single CRUD instruction returned by agy during a suggestion review.
/// `update`/`delete` reference an existing todo by `id`; `create` describes a new one.
public struct AIAction: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    public var action: Kind
    public var id: String?
    public var title: String?
    public var categories: [String]?
    public var reason: String?
    public var priority: String?

    public init(
        action: Kind,
        id: String? = nil,
        title: String? = nil,
        categories: [String]? = nil,
        reason: String? = nil,
        priority: String? = nil
    ) {
        self.action = action
        self.id = id
        self.title = title
        self.categories = categories
        self.reason = reason
        self.priority = priority
    }

    /// Lenient construction from a raw JSON dictionary, tolerating snake_case
    /// keys and missing optionals the model may emit.
    public init?(dict: [String: Any]) {
        let raw = (dict["action"] as? String ?? dict["op"] as? String ?? "").lowercased()
        guard let kind = Kind(rawValue: raw) else { return nil }
        self.action = kind
        self.id = dict["id"] as? String ?? dict["todo_id"] as? String ?? dict["todoId"] as? String
        self.title = dict["title"] as? String
        self.categories = (dict["categories"] as? [String]) ??
                          (dict["category"] as? String).map { [$0] }
        self.reason = dict["reason"] as? String
        self.priority = dict["priority"] as? String
    }
}

public struct AIActionResponse: Codable, Sendable {
    public var actions: [AIAction]
}
