import Foundation

public actor TaskBreakdownService {
    public static let shared = TaskBreakdownService()

    private init() {}

    public func breakdownTodo(todoId: String, autoAccept: Bool = false) async throws -> [TodoWithCategories] {
        let db = DatabaseService.shared
        guard let todo = try await db.fetchTodo(id: todoId) else {
            throw TaskBreakdownError.todoNotFound
        }
        let categories = try await db.fetchAllCategories()
        let categoryIds = try await getCategoryIds(for: todoId)
        let matchedCategories = categories.filter { categoryIds.contains($0.id) }
        let todoWithCats = TodoWithCategories(todo: todo, categories: matchedCategories)
        let suggestions = try await AIService.shared.breakdownTask(todoWithCats)
        var created: [TodoWithCategories] = []
        for suggestion in suggestions {
            let catIds = resolveCategoryIds(from: suggestion.categories)
            let subtask = Todo(
                title: suggestion.title,
                status: autoAccept ? .scheduled : .pending,
                priority: suggestion.priority.flatMap { Priority(rawValue: $0) },
                source: .aiSuggested,
                parentTodoId: todo.id,
                aiReason: suggestion.reason
            )
            let saved = try await db.createTodo(subtask, categoryIds: catIds)
            let cats = try await db.fetchAllCategories().filter { catIds.contains($0.id) }
            created.append(TodoWithCategories(todo: saved, categories: cats))
            if let subtasks = suggestion.subtasks {
                for sub in subtasks {
                    let item = Todo(
                        title: sub.title,
                        status: .pending,
                        source: .aiSuggested,
                        parentTodoId: saved.id,
                        aiReason: sub.reason
                    )
                    _ = try await db.createTodo(item, categoryIds: catIds)
                }
            }
        }
        return created
    }

    public func acceptSuggestion(todoId: String) async throws {
        let db = DatabaseService.shared
        try await db.scheduleTodo(id: todoId, date: Date())
    }

    public func acceptAllSuggestions() async throws -> Int {
        let db = DatabaseService.shared
        let pending = try await db.fetchPendingTodos()
        var count = 0
        for item in pending {
            try await db.scheduleTodo(id: item.todo.id)
            count += 1
        }
        return count
    }

    public func rejectSuggestion(todoId: String) async throws {
        let db = DatabaseService.shared
        try await db.dismissTodo(id: todoId)
    }

    public func rejectAllSuggestions() async throws -> Int {
        let db = DatabaseService.shared
        let pending = try await db.fetchPendingTodos()
        var count = 0
        for item in pending {
            try await db.dismissTodo(id: item.todo.id)
            count += 1
        }
        return count
    }

    public func runMorningRoutine() async throws -> [AISuggestion] {
        try await runReview(mode: .morning).created
    }

    public func runPeriodicUpdate() async throws -> [AISuggestion] {
        try await runReview(mode: .periodic).created
    }

    /// Lets agy review the current pending AI suggestions and apply CRUD:
    /// stale suggestions are deleted, weak ones updated, and genuinely-needed
    /// new ones created. Destructive actions are confined to the AI's own
    /// pending suggestions — user-owned todos (manual/scheduled/completed) are
    /// never touched, regardless of what agy returns.
    @discardableResult
    public func runReview(mode: AIService.ReviewMode) async throws -> ReviewResult {
        let db = DatabaseService.shared

        // Deterministic cleanup first: drop yesterday's never-accepted AI
        // suggestions. This reliably removes stale items and shrinks the prompt
        // so agy's review stays fast and focused on what's still relevant today.
        var deletedCount = try await db.deleteStalePendingSuggestions(before: DateHelpers.startOfDay())

        let context = try await buildContext()
        let actions = try await AIService.shared.reviewSuggestions(context: context, mode: mode)

        // Ids the AI is allowed to mutate: its own still-pending suggestions.
        let editableIds = Set(context.pendingSuggestions.map(\.id))
        var existingTitles = context.allActiveTitles

        var created: [AISuggestion] = []
        var updatedCount = 0

        for action in actions {
            switch action.action {
            case .delete:
                guard let id = action.id, editableIds.contains(id) else { continue }
                try await db.deleteTodo(id: id)
                deletedCount += 1

            case .update:
                guard let id = action.id, editableIds.contains(id),
                      var todo = try await db.fetchTodo(id: id),
                      todo.sourceEnum == .aiSuggested, todo.statusEnum == .pending
                else { continue }
                if let title = action.title, !title.isEmpty { todo.title = title }
                if let priority = action.priority { todo.priorityEnum = Priority(rawValue: priority) }
                if let reason = action.reason, !reason.isEmpty { todo.aiReason = reason }
                _ = try await db.updateTodo(todo)
                if let cats = action.categories, !cats.isEmpty {
                    try await db.setTodoCategories(todoId: id, categoryIds: resolveCategoryIds(from: cats))
                }
                updatedCount += 1

            case .create:
                guard let title = action.title, !title.isEmpty else { continue }
                let suggestion = AISuggestion(
                    title: title,
                    categories: action.categories ?? [],
                    reason: action.reason ?? "",
                    priority: action.priority
                )
                guard !deduplicate([suggestion], against: existingTitles).isEmpty else { continue }
                let categoryIds = resolveCategoryIds(from: suggestion.categories)
                let todo = Todo(
                    title: suggestion.title,
                    status: .pending,
                    priority: suggestion.priority.flatMap { Priority(rawValue: $0) },
                    source: .aiSuggested,
                    aiReason: suggestion.reason
                )
                _ = try await db.createTodo(todo, categoryIds: categoryIds)
                created.append(suggestion)
                existingTitles.append(suggestion.title)   // avoid dupes within same batch
            }
        }

        return ReviewResult(created: created, updatedCount: updatedCount, deletedCount: deletedCount)
    }

    private func buildContext() async throws -> AIContext {
        let db = DatabaseService.shared
        let events = try await db.fetchCalendarEvents(from: Date(), to: DateHelpers.daysFromNow(7))
        let allTodos = try await db.fetchAllTodos(status: nil)
        let todayStart = DateHelpers.startOfDay()
        let todayEnd = DateHelpers.endOfDay()

        let eventInfos = events.map { e -> AIContext.CalendarEventInfo in
            AIContext.CalendarEventInfo(
                title: e.title,
                start: e.startTime.map { DateHelpers.displayDateTimeFormatter.string(from: $0) },
                end: e.endTime.map { DateHelpers.displayDateTimeFormatter.string(from: $0) },
                calendar: e.calendarName
            )
        }

        let toInfo = { (t: TodoWithCategories) -> AIContext.TodoInfo in
            AIContext.TodoInfo(
                id: t.todo.id,
                title: t.todo.title,
                status: t.todo.status,
                priority: t.todo.priority,
                categories: t.categories.map(\.name).joined(separator: ","),
                source: t.todo.source,
                aiReason: t.todo.aiReason,
                created: DateHelpers.isoDateFormatter.string(from: t.todo.createdAt)
            )
        }

        let scheduledToday = allTodos.filter {
            $0.todo.statusEnum == .scheduled && $0.todo.scheduledDate != nil &&
            $0.todo.scheduledDate! >= todayStart && $0.todo.scheduledDate! <= todayEnd
        }

        let completedToday = allTodos.filter {
            $0.todo.statusEnum == .completed && $0.todo.completedAt != nil &&
            $0.todo.completedAt! >= todayStart && $0.todo.completedAt! <= todayEnd
        }

        let pendingSuggestions = allTodos.filter {
            $0.todo.statusEnum == .pending && $0.todo.sourceEnum == .aiSuggested
        }

        let recentlyDismissed = allTodos.filter {
            $0.todo.statusEnum == .dismissed && $0.todo.updatedAt >= todayStart
        }

        let allActiveTitles = allTodos.filter {
            $0.todo.statusEnum != .dismissed
        }.map { $0.todo.title }

        return AIContext(
            date: DateHelpers.displayDateFormatter.string(from: Date()),
            time: DateHelpers.displayDateTimeFormatter.string(from: Date()),
            events: eventInfos,
            scheduledToday: scheduledToday.map(toInfo),
            completedToday: completedToday.map(toInfo),
            pendingSuggestions: pendingSuggestions.map(toInfo),
            recentlyDismissed: recentlyDismissed.map(toInfo),
            allActiveTitles: allActiveTitles
        )
    }

    private func resolveCategoryIds(from categoryNames: [String]) -> [String] {
        let nameMap: [String: String] = [
            "work": "work", "업무": "work",
            "personal": "personal", "개인": "personal",
        ]
        return categoryNames.compactMap { nameMap[$0.lowercased()] }.uniqued()
    }

    private func deduplicate(_ suggestions: [AISuggestion], against existingTitles: [String]) -> [AISuggestion] {
        let normalized = Set(existingTitles.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        return suggestions.filter { suggestion in
            let title = suggestion.title.lowercased().trimmingCharacters(in: .whitespaces)
            guard !normalized.contains(title) else { return false }
            let similar = normalized.contains { existing in
                let shorter = min(existing.count, title.count)
                guard shorter > 3 else { return false }
                return existing.contains(title) || title.contains(existing)
            }
            return !similar
        }
    }

    private func getCategoryIds(for todoId: String) async throws -> [String] {
        let db = DatabaseService.shared
        let todoWithCats = try await db.fetchAllTodos()
        return todoWithCats.first(where: { $0.todo.id == todoId })?.categories.map(\.id) ?? []
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

public struct ReviewResult: Sendable {
    public let created: [AISuggestion]
    public let updatedCount: Int
    public let deletedCount: Int

    public var hasChanges: Bool {
        !created.isEmpty || updatedCount > 0 || deletedCount > 0
    }
}

public enum TaskBreakdownError: LocalizedError {
    case todoNotFound

    public var errorDescription: String? {
        switch self {
        case .todoNotFound: "Todo not found."
        }
    }
}
