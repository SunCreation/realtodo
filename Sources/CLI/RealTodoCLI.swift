import Foundation
import ArgumentParser
import RealTodoKit

@main
struct RealTodoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "real_todo",
        abstract: "RealTodo — macOS menu bar todo app CLI",
        version: "1.0.0",
        subcommands: [
            TodayCommand.self,
            ListCommand.self,
            ShowCommand.self,
            AddCommand.self,
            EditCommand.self,
            DoneCommand.self,
            ScheduleCommand.self,
            UnscheduleCommand.self,
            DeleteCommand.self,
            AnalyzeCommand.self,
            RolloverCommand.self,
            TimeCommand.self,
            ReviewCommand.self,
            BreakdownCommand.self,
            SuggestionsCommand.self,
            CalendarCommand.self,
            CategoryCommand.self,
            StatsCommand.self,
            ConfigCommand.self,
        ]
    )
}

struct CommonOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output format: table or json")
    var format: OutputFormat = .table

    @Option(name: .shortAndLong, help: "Filter by category (comma-separated for multiple)")
    var category: String?

    @Option(name: .long, help: "Filter by status")
    var status: TodoStatus?

    @Option(name: .long, help: "Filter by source")
    var source: TodoSource?
}

enum OutputFormat: String, ExpressibleByArgument {
    case table
    case json
}

// MARK: - Today

struct TodayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "today",
        abstract: "Show today's scheduled todos"
    )

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        let db = DatabaseService.shared
        let todos = try await db.fetchTodayTodos()
        let filtered = applyFilters(todos)
        if common.format.rawValue == "json" {
            print(OutputFormatter.formatTodayJSON(filtered))
        } else {
            print(OutputFormatter.formatTodos(filtered, format: .table))
        }
    }

    private func applyFilters(_ todos: [TodoWithCategories]) -> [TodoWithCategories] {
        var result = todos
        if let cat = common.category {
            let names = cat.split(separator: ",").map(String.init)
            result = result.filter { item in
                item.categories.contains { c in names.contains(c.name) || names.contains(c.id) }
            }
        }
        if let status = common.status {
            result = result.filter { $0.todo.statusEnum == status }
        }
        return result
    }
}

// MARK: - List

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all todos"
    )

    @OptionGroup var common: CommonOptions

    @Option(name: .long, help: "Filter by date (yyyy-MM-dd)")
    var date: String?

    mutating func run() async throws {
        let db = DatabaseService.shared
        let dateFilter = date.flatMap { DateHelpers.isoDateFormatter.date(from: $0) }
        var todos = try await db.fetchAllTodos(status: common.status, source: common.source, scheduledDate: dateFilter)
        if let cat = common.category {
            let names = cat.split(separator: ",").map(String.init)
            todos = todos.filter { item in
                item.categories.contains { c in names.contains(c.name) || names.contains(c.id) }
            }
        }
        let format: OutputFormatter.Format = common.format.rawValue == "json" ? .json : .table
        print(OutputFormatter.formatTodos(todos, format: format))
    }
}

// MARK: - Show

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show todo detail")

    @Argument(help: "Todo ID")
    var id: String

    @Flag(name: .long, help: "Include subtasks")
    var withSubtasks = false

    mutating func run() async throws {
        let db = DatabaseService.shared
        guard let todo = try await db.fetchTodo(id: id) else {
            throw ValidationError("Todo not found: \(id)")
        }
        let cats = try await db.fetchAllCategories()
        let categoryIds = try await db.fetchAllTodos().first(where: { $0.todo.id == id })?.categories ?? []
        let item = TodoWithCategories(todo: todo, categories: categoryIds)
        var subtasks: [TodoWithCategories] = []
        if withSubtasks {
            subtasks = try await db.fetchSubtasks(parentTodoId: id)
        }
        print(OutputFormatter.formatTodoDetail(item, subtasks: subtasks))
    }
}

// MARK: - Add

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a new todo")

    @Argument(help: "Todo title (use '-' for stdin)")
    var title: String

    @Option(name: .shortAndLong, help: "Category IDs (comma-separated)")
    var category: String?

    @Option(name: .long, help: "Priority: high, medium, low")
    var priority: Priority?

    @Option(name: .long, help: "Due date (yyyy-MM-dd)")
    var due: String?

    @Option(name: .long, help: "Status: pending or scheduled")
    var status: TodoStatus = .scheduled

    @Flag(name: .long, help: "Read multiple todos from stdin (one per line)")
    var batch = false

    mutating func run() async throws {
        let db = DatabaseService.shared
        let categoryIds = category?.split(separator: ",").map(String.init) ?? []
        let dueDate = due.flatMap { DateHelpers.isoDateFormatter.date(from: $0) }

        if batch || title == "-" {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let text = String(data: input, encoding: .utf8) ?? ""
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines {
                let todo = Todo(title: line, status: status, priority: priority, source: .manual, dueDate: dueDate, scheduledDate: status == .scheduled ? Date() : nil)
                let saved = try await db.createTodo(todo, categoryIds: categoryIds)
                print("Added: \(saved.id) - \(saved.title)")
            }
        } else {
            let todo = Todo(title: title, status: status, priority: priority, source: .manual, dueDate: dueDate, scheduledDate: status == .scheduled ? Date() : nil)
            let saved = try await db.createTodo(todo, categoryIds: categoryIds)
            print("Added: \(saved.id) - \(saved.title)")
        }
    }
}

// MARK: - Edit

struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit", abstract: "Edit a todo")

    @Argument(help: "Todo ID")
    var id: String

    @Option(name: .long, help: "New title")
    var title: String?

    @Option(name: .shortAndLong, help: "Category IDs (comma-separated)")
    var category: String?

    @Option(name: .long, help: "Priority: high, medium, low")
    var priority: Priority?

    @Option(name: .long, help: "Due date (yyyy-MM-dd)")
    var due: String?

    mutating func run() async throws {
        let db = DatabaseService.shared
        guard var todo = try await db.fetchTodo(id: id) else {
            throw ValidationError("Todo not found: \(id)")
        }
        if let title { todo.title = title }
        if let priority { todo.priority = priority.rawValue }
        if let due {
            todo.dueDate = DateHelpers.isoDateFormatter.date(from: due)
        }
        _ = try await db.updateTodo(todo)
        if let category {
            let ids = category.split(separator: ",").map(String.init)
            try await db.setTodoCategories(todoId: id, categoryIds: ids)
        }
        print("Updated: \(id)")
    }
}

// MARK: - Done

struct DoneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "done", abstract: "Mark todo(s) as completed")

    @Argument(help: "Todo ID(s)")
    var ids: [String]

    mutating func run() async throws {
        let db = DatabaseService.shared
        for id in ids {
            try await db.completeTodo(id: id)
            print("Completed: \(id)")
        }
    }
}

// MARK: - Schedule

struct ScheduleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schedule", abstract: "Move todo to today's list")

    @Argument(help: "Todo ID")
    var id: String

    @Option(name: .long, help: "Schedule for specific date (yyyy-MM-dd)")
    var date: String?

    mutating func run() async throws {
        let db = DatabaseService.shared
        let dateValue = date.flatMap { DateHelpers.isoDateFormatter.date(from: $0) } ?? Date()
        try await db.scheduleTodo(id: id, date: dateValue)
        print("Scheduled: \(id) for \(DateHelpers.isoDateFormatter.string(from: DateHelpers.startOfDay(dateValue)))")
    }
}

// MARK: - Unschedule

struct UnscheduleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unschedule", abstract: "Move todo back to all todos")

    @Argument(help: "Todo ID")
    var id: String

    mutating func run() async throws {
        let db = DatabaseService.shared
        try await db.unscheduleTodo(id: id)
        print("Unscheduled: \(id)")
    }
}

// MARK: - Delete

struct DeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a todo")

    @Argument(help: "Todo ID")
    var id: String

    @Flag(name: .long, help: "Skip confirmation")
    var force = false

    mutating func run() async throws {
        if !force {
            print("Delete todo \(id)? [y/N] ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "y" else {
                print("Cancelled.")
                return
            }
        }
        let db = DatabaseService.shared
        try await db.deleteTodo(id: id)
        print("Deleted: \(id)")
    }
}

// MARK: - Analyze

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "analyze", abstract: "Run AI morning routine analysis")

    @Flag(name: .long, help: "Force full re-analysis")
    var full = false

    mutating func run() async throws {
        if full {
            let db = DatabaseService.shared
            let all = try await db.fetchAllTodos(status: .pending, source: .aiSuggested)
            for item in all {
                try await db.deleteTodo(id: item.todo.id)
            }
            print("Cleared \(all.count) existing AI suggestions for full re-analysis.")
        }
        print("Running AI analysis...")
        let suggestions = try await TaskBreakdownService.shared.runMorningRoutine()
        if suggestions.isEmpty {
            print("No new suggestions generated.")
        } else {
            print("Generated \(suggestions.count) suggestions:")
            for (i, s) in suggestions.enumerated() {
                print("  \(i + 1). \(s.title) [\(s.categories.joined(separator: ","))] - \(s.reason)")
            }
            print("\nUse `real_todo suggestions` to review and accept/reject.")
        }
    }
}

// MARK: - Time

struct TimeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "time",
        abstract: "Assign a time slot to a todo (e.g. 09:00-10:00 or 14:00)")

    @Argument(help: "Todo ID")
    var id: String

    @Argument(help: "Time slot: \"HH:mm\" or \"HH:mm-HH:mm\". Omit with --clear to remove.")
    var slot: String?

    @Flag(name: .long, help: "Clear the time slot")
    var clear = false

    mutating func run() async throws {
        let db = DatabaseService.shared
        guard try await db.fetchTodo(id: id) != nil else {
            print("Todo not found: \(id)")
            return
        }
        if clear {
            try await db.setTodoTime(id: id, startMinute: nil, endMinute: nil)
            print("Cleared time slot.")
            return
        }
        guard let slot else {
            print("Provide a time slot (e.g. 09:00-10:00) or use --clear.")
            return
        }
        let parts = slot.split(separator: "-", maxSplits: 1).map { String($0) }
        guard let start = DateHelpers.parseMinutes(parts[0]) else {
            print("Invalid start time: \(parts[0]). Use HH:mm.")
            return
        }
        var end: Int? = nil
        if parts.count == 2 {
            guard let e = DateHelpers.parseMinutes(parts[1]) else {
                print("Invalid end time: \(parts[1]). Use HH:mm.")
                return
            }
            end = e
        }
        try await db.setTodoTime(id: id, startMinute: start, endMinute: end)
        let label = end != nil
            ? "\(DateHelpers.formatMinutes(start)!)-\(DateHelpers.formatMinutes(end)!)"
            : DateHelpers.formatMinutes(start)!
        print("Set time slot: \(label)")
    }
}

// MARK: - Rollover

struct RolloverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rollover",
        abstract: "Carry yesterday's unfinished today-todos forward to today")

    mutating func run() async throws {
        let count = try await TimerService.shared.runRollover()
        if count == 0 {
            print("Nothing to roll over.")
        } else {
            print("Rolled \(count) unfinished todo(s) forward to today.")
        }
    }
}

// MARK: - Review

struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Let AI review pending suggestions and apply CRUD (delete stale, update, create new)")

    @Flag(name: .long, help: "Use periodic (mid-day) review tone instead of morning")
    var periodic = false

    mutating func run() async throws {
        print("Reviewing AI suggestions...")
        let result = try await TaskBreakdownService.shared.runReview(mode: periodic ? .periodic : .morning)
        if !result.hasChanges {
            print("No changes — suggestions are up to date.")
            return
        }
        print("Deleted \(result.deletedCount), updated \(result.updatedCount), created \(result.created.count).")
        for (i, s) in result.created.enumerated() {
            print("  + \(i + 1). \(s.title) [\(s.categories.joined(separator: ","))] - \(s.reason)")
        }
        print("\nUse `real_todo suggestions` to accept/reject.")
    }
}

// MARK: - Breakdown

struct BreakdownCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "breakdown", abstract: "Break down a todo into subtasks using AI")

    @Argument(help: "Todo ID")
    var id: String

    @Flag(name: .long, help: "Auto-accept all generated subtasks")
    var acceptAll = false

    mutating func run() async throws {
        print("Breaking down todo \(id)...")
        let subtasks = try await TaskBreakdownService.shared.breakdownTodo(todoId: id, autoAccept: acceptAll)
        if subtasks.isEmpty {            print("No subtasks generated.")
        } else {
            print("Generated \(subtasks.count) subtasks:")
            for (i, item) in subtasks.enumerated() {
                print("  \(i + 1). \(item.todo.title)")
            }
        }
    }
}

// MARK: - Suggestions

struct SuggestionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "suggestions", abstract: "Manage AI suggestions")

    @Option(name: .long, help: "Accept a specific suggestion by ID")
    var accept: String?

    @Flag(name: .long, help: "Accept all pending suggestions")
    var acceptAll = false

    @Option(name: .long, help: "Reject a specific suggestion by ID")
    var reject: String?

    @Flag(name: .long, help: "Reject all pending suggestions")
    var rejectAll = false

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        let db = DatabaseService.shared
        if let acceptId = accept {
            try await db.scheduleTodo(id: acceptId)
            print("Accepted: \(acceptId)")
            return
        }
        if acceptAll {
            let count = try await TaskBreakdownService.shared.acceptAllSuggestions()
            print("Accepted \(count) suggestions.")
            return
        }
        if let rejectId = reject {
            try await db.dismissTodo(id: rejectId)
            print("Rejected: \(rejectId)")
            return
        }
        if rejectAll {
            let count = try await TaskBreakdownService.shared.rejectAllSuggestions()
            print("Rejected \(count) suggestions.")
            return
        }
        let pending = try await db.fetchPendingTodos()
        let format: OutputFormatter.Format = common.format.rawValue == "json" ? .json : .table
        print("Pending AI suggestions (\(pending.count)):")
        print(OutputFormatter.formatTodos(pending, format: format))
    }
}

// MARK: - Calendar

struct CalendarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "Manage Google Calendar integration",
        subcommands: [
            CalendarSyncCommand.self,
            CalendarListCommand.self,
            CalendarMapCommand.self,
            CalendarUnmapCommand.self,
            CalendarEventsCommand.self,
        ]
    )
}

struct CalendarSyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sync", abstract: "Sync Google Calendar events")
    mutating func run() async throws {
        print("Syncing calendars...")
        let events = try await CalendarService.shared.syncAllMappedCalendars()
        print("Synced \(events.count) events.")
    }
}

struct CalendarListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List connected calendars")
    mutating func run() async throws {
        let calendars = try await CalendarService.shared.fetchCalendars()
        for cal in calendars {
            print("  \(cal.id) — \(cal.summary)\(cal.primary == true ? " (primary)" : "")")
        }
    }
}

struct CalendarMapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "map", abstract: "Map a calendar to a category")

    @Option(name: .long, help: "Google Calendar ID")
    var calendarId: String

    @Option(name: .long, help: "Category ID (work or personal)")
    var category: String

    mutating func run() async throws {
        let db = DatabaseService.shared
        let calendars = try await CalendarService.shared.fetchCalendars()
        guard let cal = calendars.first(where: { $0.id == calendarId }) else {
            throw ValidationError("Calendar not found: \(calendarId)")
        }
        try await db.setCalendarMapping(calendarId: calendarId, calendarName: cal.summary, categoryId: category)
        print("Mapped \(cal.summary) → \(category)")
    }
}

struct CalendarUnmapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unmap", abstract: "Remove calendar mapping")

    @Argument(help: "Google Calendar ID")
    var calendarId: String

    mutating func run() async throws {
        let db = DatabaseService.shared
        try await db.removeCalendarMapping(calendarId: calendarId)
        print("Unmapped: \(calendarId)")
    }
}

struct CalendarEventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "events", abstract: "Show today's calendar events")

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        let db = DatabaseService.shared
        let events = try await db.fetchCalendarEvents(from: Date(), to: DateHelpers.endOfDay())
        if events.isEmpty {
            print("No events today.")
        } else {
            for event in events {
                let start = event.startTime.map { DateHelpers.displayTimeFormatter.string(from: $0) } ?? "?"
                let end = event.endTime.map { DateHelpers.displayTimeFormatter.string(from: $0) } ?? "?"
                print("  \(start)-\(end) \(event.title ?? "Untitled") [\(event.calendarName ?? "")]")
            }
        }
    }
}

// MARK: - Category

struct CategoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "category",
        abstract: "Manage categories",
        subcommands: [CategoryListCommand.self, CategoryAddCommand.self, CategoryDeleteCommand.self]
    )
}

struct CategoryListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List categories")
    mutating func run() async throws {
        let db = DatabaseService.shared
        let categories = try await db.fetchAllCategories()
        for cat in categories {
            print("  \(cat.id) — \(cat.name) \(OutputFormatter.colorDot(cat.color))")
        }
    }
}

struct CategoryAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a category")

    @Argument(help: "Category name")
    var name: String

    @Option(name: .long, help: "Hex color (e.g. #F59E0B)")
    var color: String = "#F59E0B"

    mutating func run() async throws {
        let db = DatabaseService.shared
        let existing = try await db.fetchAllCategories()
        let cat = Category(name: name, color: color, sortOrder: existing.count)
        _ = try await db.createCategory(cat)
        print("Added category: \(name)")
    }
}

struct CategoryDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a category")

    @Argument(help: "Category ID")
    var id: String

    mutating func run() async throws {
        let db = DatabaseService.shared
        try await db.deleteCategory(id: id)
        print("Deleted category: \(id)")
    }
}

// MARK: - Stats

struct StatsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stats", abstract: "Show todo statistics")

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        let db = DatabaseService.shared
        let stats = try await db.fetchStats()
        let format: OutputFormatter.Format = common.format.rawValue == "json" ? .json : .table
        print(OutputFormatter.formatStats(stats, format: format))
    }
}

// MARK: - Config

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage app settings",
        subcommands: [ConfigGetCommand.self, ConfigSetCommand.self, ConfigListCommand.self]
    )
}

struct ConfigGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get a setting value")

    @Argument(help: "Setting key")
    var key: String

    mutating func run() async throws {
        let db = DatabaseService.shared
        if let value = try await db.getSetting(key) {
            print("\(key) = \(value)")
        } else {
            print("\(key) = (not set)")
        }
    }
}

struct ConfigSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a setting value")

    @Argument(help: "Setting key")
    var key: String

    @Argument(help: "Setting value")
    var value: String

    mutating func run() async throws {
        let db = DatabaseService.shared
        try await db.setSetting(key, value: value)
        print("Set \(key) = \(value)")
    }
}

struct ConfigListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List all settings")
    mutating func run() async throws {
        let db = DatabaseService.shared
        let settings = try await db.getAllSettings()
        if settings.isEmpty {
            print("No settings configured.")
        } else {
            for (key, value) in settings.sorted(by: { $0.key < $1.key }) {
                print("  \(key) = \(value)")
            }
        }
    }
}
