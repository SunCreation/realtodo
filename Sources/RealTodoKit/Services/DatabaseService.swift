import Foundation
import GRDB

public actor DatabaseService {
    public static let shared = DatabaseService()

    private var dbPool: DatabasePool!

    private init() {
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA foreign_keys=ON")
            }
            let pool = try DatabasePool(path: AppConstants.databasePath, configuration: config)
            try Self.buildMigrator().migrate(pool)
            dbPool = pool
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private static func buildMigrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_initial") { db in
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
            }
            try db.create(table: "todos") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("priority", .text)
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("parent_event_id", .text)
                t.column("parent_todo_id", .text)
                t.column("calendar_id", .text)
                t.column("due_date", .datetime)
                t.column("scheduled_date", .datetime)
                t.column("completed_at", .datetime)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("ai_reason", .text)
                t.column("created_at", .datetime).notNull().defaults(to: Date())
                t.column("updated_at", .datetime).notNull().defaults(to: Date())
            }
            try db.create(table: "todo_categories") { t in
                t.column("todo_id", .text).notNull().references("todos", onDelete: .cascade)
                t.column("category_id", .text).notNull().references("categories", onDelete: .cascade)
                t.primaryKey(["todo_id", "category_id"])
            }
            try db.create(table: "calendar_events") { t in
                t.column("id", .text).primaryKey()
                t.column("calendar_id", .text).notNull()
                t.column("calendar_name", .text)
                t.column("title", .text)
                t.column("start_time", .datetime)
                t.column("end_time", .datetime)
                t.column("description", .text)
                t.column("synced_at", .datetime)
            }
            try db.create(table: "calendar_mappings") { t in
                t.column("calendar_id", .text).primaryKey()
                t.column("calendar_name", .text).notNull()
                t.column("category_id", .text).notNull().references("categories", onDelete: .cascade)
            }
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
            try db.execute(sql: """
                INSERT INTO categories (id, name, color, sortOrder) VALUES ('work', '업무', '#3B82F6', 0);
                INSERT INTO categories (id, name, color, sortOrder) VALUES ('personal', '개인', '#22C55E', 1);
            """)
        }
        m.registerMigration("v2_google_accounts") { db in
            try db.create(table: "google_accounts") { t in
                t.column("id", .text).primaryKey()
                t.column("email", .text).notNull()
                t.column("display_name", .text)
                t.column("access_token", .text).notNull()
                t.column("refresh_token", .text)
                t.column("expiration_date", .datetime).notNull()
                t.column("scope", .text)
                t.column("created_at", .datetime).notNull().defaults(to: Date())
            }
            try db.alter(table: "calendar_mappings") { t in
                t.add(column: "account_id", .text)
            }
        }
        m.registerMigration("v3_todo_timeslots") { db in
            try db.alter(table: "todos") { t in
                t.add(column: "start_minute", .integer)
                t.add(column: "end_minute", .integer)
            }
        }
        return m
    }

    // MARK: - Google Accounts

    public func createAccount(_ account: GoogleAccount) throws -> GoogleAccount {
        try dbPool.write { db in
            var account = account
            try account.insert(db)
            return account
        }
    }

    public func fetchAllAccounts() throws -> [GoogleAccount] {
        try dbPool.read { db in
            try GoogleAccount.order(Column("created_at").asc).fetchAll(db)
        }
    }

    public func fetchAccount(id: String) throws -> GoogleAccount? {
        try dbPool.read { db in
            try GoogleAccount.fetchOne(db, key: id)
        }
    }

    public func updateAccount(_ account: GoogleAccount) throws {
        try dbPool.write { db in
            try account.update(db)
        }
    }

    public func deleteAccount(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM calendar_mappings WHERE account_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM google_accounts WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Todo CRUD

    public func createTodo(_ todo: Todo, categoryIds: [String] = []) throws -> Todo {
        try dbPool.write { db in
            var todo = todo
            todo.updatedAt = Date()
            try todo.insert(db)
            for catId in Set(categoryIds) {
                try db.execute(sql: "INSERT INTO todo_categories (todo_id, category_id) VALUES (?, ?)",
                               arguments: [todo.id, catId])
            }
            return todo
        }
    }

    public func updateTodo(_ todo: Todo) throws -> Todo {
        try dbPool.write { db in
            var updated = todo
            updated.updatedAt = Date()
            try updated.update(db)
            return updated
        }
    }

    public func deleteTodo(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM todos WHERE id = ?", arguments: [id])
        }
    }

    public func fetchTodo(id: String) throws -> Todo? {
        try dbPool.read { db in
            try Todo.fetchOne(db, key: id)
        }
    }

    public func fetchAllTodos(
        status: TodoStatus? = nil,
        source: TodoSource? = nil,
        scheduledDate: Date? = nil,
        categoryIds: [String] = [],
        includeSubtasks: Bool = false
    ) throws -> [TodoWithCategories] {
        try dbPool.read { db in
            var query = Todo.all()
            if let status {
                query = query.filter(Column("status") == status.rawValue)
            }
            if let source {
                query = query.filter(Column("source") == source.rawValue)
            }
            if let scheduledDate {
                let start = DateHelpers.startOfDay(scheduledDate)
                let end = DateHelpers.endOfDay(scheduledDate)
                query = query.filter(
                    Column("scheduled_date") >= start && Column("scheduled_date") <= end
                )
            }
            if !includeSubtasks {
                query = query.filter(Column("parent_todo_id") == nil)
            }
            query = query.order(Column("sort_order").asc, Column("created_at").desc)
            let todos = try query.fetchAll(db)
            return try todos.map { todo in
                let categories = try Category.fetchAll(db,
                    sql: """
                    SELECT c.* FROM categories c
                    JOIN todo_categories tc ON c.id = tc.category_id
                    WHERE tc.todo_id = ?
                    """,
                    arguments: [todo.id])
                return TodoWithCategories(todo: todo, categories: categories)
            }
        }
    }

    public func fetchTodayTodos() throws -> [TodoWithCategories] {
        try dbPool.read { db in
            let start = DateHelpers.startOfDay()
            let end = DateHelpers.endOfDay()
            let todos = try Todo.filter(
                (Column("status") == TodoStatus.scheduled.rawValue &&
                 Column("scheduled_date") >= start && Column("scheduled_date") <= end) ||
                (Column("status") == TodoStatus.completed.rawValue &&
                 Column("completed_at") >= start && Column("completed_at") <= end)
            )
            .filter(Column("parent_todo_id") == nil)
            // Timed items first, ascending by start time; untimed items last.
            .order(
                Column("start_minute") == nil,
                Column("start_minute").asc,
                Column("sort_order").asc,
                Column("created_at").desc
            )
            .fetchAll(db)
            return try todos.map { todo in
                let categories = try Category.fetchAll(db,
                    sql: """
                    SELECT c.* FROM categories c
                    JOIN todo_categories tc ON c.id = tc.category_id
                    WHERE tc.todo_id = ?
                    """,
                    arguments: [todo.id])
                return TodoWithCategories(todo: todo, categories: categories)
            }
        }
    }

    public func fetchPendingTodos() throws -> [TodoWithCategories] {
        try fetchAllTodos(status: .pending)
    }

    public func fetchSubtasks(parentTodoId: String) throws -> [TodoWithCategories] {
        try dbPool.read { db in
            let todos = try Todo.filter(Column("parent_todo_id") == parentTodoId)
                .order(Column("sort_order").asc)
                .fetchAll(db)
            return try todos.map { todo in
                let categories = try Category.fetchAll(db,
                    sql: """
                    SELECT c.* FROM categories c
                    JOIN todo_categories tc ON c.id = tc.category_id
                    WHERE tc.todo_id = ?
                    """,
                    arguments: [todo.id])
                return TodoWithCategories(todo: todo, categories: categories)
            }
        }
    }

    public func scheduleTodo(id: String, date: Date = Date()) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE todos SET status = 'scheduled', scheduled_date = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [DateHelpers.startOfDay(date), Date(), id])
        }
    }

    public func unscheduleTodo(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE todos SET status = 'pending', scheduled_date = NULL, updated_at = ?
                WHERE id = ?
            """, arguments: [Date(), id])
        }
    }

    public func completeTodo(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE todos SET status = 'completed', completed_at = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [Date(), Date(), id])
        }
    }

    /// Deletes AI-suggested todos still pending (never accepted) that were
    /// created before `before`. Used to auto-clear yesterday's stale suggestions.
    /// Scoped to source='ai_suggested' AND status='pending' so user-owned and
    /// already-accepted todos are never affected. Returns the number removed.
    @discardableResult
    public func deleteStalePendingSuggestions(before: Date) throws -> Int {
        try dbPool.write { db in
            try db.execute(sql: """
                DELETE FROM todos
                WHERE source = 'ai_suggested' AND status = 'pending' AND created_at < ?
            """, arguments: [before])
            return db.changesCount
        }
    }

    /// Carries unfinished "today" todos forward: any scheduled or in-progress
    /// todo whose scheduled_date is before `today` is re-dated to `today` so it
    /// stays on the user's plate instead of being stranded in the past.
    /// Completed/dismissed/pending items are untouched. Returns the number moved.
    @discardableResult
    public func rolloverUnfinishedTodos(to today: Date) throws -> Int {
        let startOfToday = DateHelpers.startOfDay(today)
        return try dbPool.write { db in
            try db.execute(sql: """
                UPDATE todos SET scheduled_date = ?, updated_at = ?
                WHERE status IN ('scheduled', 'in_progress')
                  AND scheduled_date IS NOT NULL
                  AND scheduled_date < ?
            """, arguments: [startOfToday, Date(), startOfToday])
            return db.changesCount
        }
    }

    public func dismissTodo(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE todos SET status = 'dismissed', updated_at = ? WHERE id = ?
            """, arguments: [Date(), id])
        }
    }

    /// Assigns (or clears) a time-of-day slot for a todo. Minutes are 0...1439
    /// from midnight; pass nil to clear. Used for daily time-blocking.
    public func setTodoTime(id: String, startMinute: Int?, endMinute: Int?) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE todos SET start_minute = ?, end_minute = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [startMinute, endMinute, Date(), id])
        }
    }

    public func setTodoCategories(todoId: String, categoryIds: [String]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM todo_categories WHERE todo_id = ?", arguments: [todoId])
            for catId in Set(categoryIds) {
                try db.execute(sql: "INSERT INTO todo_categories (todo_id, category_id) VALUES (?, ?)",
                               arguments: [todoId, catId])
            }
        }
    }

    // MARK: - Category CRUD

    public func fetchAllCategories() throws -> [Category] {
        try dbPool.read { db in
            try Category.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    public func createCategory(_ category: Category) throws -> Category {
        try dbPool.write { db in
            var cat = category
            try cat.insert(db)
            return cat
        }
    }

    public func deleteCategory(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Calendar Events

    public func saveCalendarEvents(_ events: [CalendarEvent]) throws {
        try dbPool.write { db in
            for var event in events {
                event.syncedAt = Date()
                try event.save(db)
            }
        }
    }

    public func fetchCalendarEvents(from: Date? = nil, to: Date? = nil) throws -> [CalendarEvent] {
        try dbPool.read { db in
            var query = CalendarEvent.all()
            if let from {
                query = query.filter(Column("start_time") >= from)
            }
            if let to {
                query = query.filter(Column("end_time") <= to)
            }
            return try query.order(Column("start_time").asc).fetchAll(db)
        }
    }

    // MARK: - Calendar Mappings

    public func fetchCalendarMappings() throws -> [CalendarMapping] {
        try dbPool.read { db in
            try CalendarMapping.fetchAll(db)
        }
    }

    public func fetchCalendarMappings(accountId: String) throws -> [CalendarMapping] {
        try dbPool.read { db in
            try CalendarMapping
                .filter(Column("account_id") == accountId)
                .fetchAll(db)
        }
    }

    public func setCalendarMapping(accountId: String? = nil, calendarId: String, calendarName: String, categoryId: String) throws {
        try dbPool.write { db in
            var mapping = CalendarMapping(accountId: accountId, calendarId: calendarId, calendarName: calendarName, categoryId: categoryId)
            try mapping.save(db)
        }
    }

    public func removeCalendarMapping(calendarId: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM calendar_mappings WHERE calendar_id = ?", arguments: [calendarId])
        }
    }

    public func removeCalendarMapping(accountId: String?, calendarId: String) throws {
        try dbPool.write { db in
            if let accountId {
                try db.execute(sql: "DELETE FROM calendar_mappings WHERE account_id = ? AND calendar_id = ?", arguments: [accountId, calendarId])
            } else {
                try db.execute(sql: "DELETE FROM calendar_mappings WHERE account_id IS NULL AND calendar_id = ?", arguments: [calendarId])
            }
        }
    }

    // MARK: - Settings

    public func getSetting(_ key: String) throws -> String? {
        try dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    public func setSetting(_ key: String, value: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                           arguments: [key, value])
        }
    }

    public func getAllSettings() throws -> [String: String] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
            var result: [String: String] = [:]
            for row in rows {
                result[row["key"]] = row["value"]
            }
            return result
        }
    }

    // MARK: - Stats

    public func fetchStats() throws -> TodoStats {
        try dbPool.read { db in
            let total = try Todo.filter(Column("status") != "dismissed").fetchCount(db)
            let completed = try Todo.filter(Column("status") == "completed").fetchCount(db)
            let todayScheduled = try Todo.filter(
                Column("status") == "scheduled" &&
                Column("scheduled_date") >= DateHelpers.startOfDay() &&
                Column("scheduled_date") <= DateHelpers.endOfDay()
            ).fetchCount(db)
            let todayCompleted = try Todo.filter(
                Column("status") == "completed" &&
                Column("completed_at") >= DateHelpers.startOfDay() &&
                Column("completed_at") <= DateHelpers.endOfDay()
            ).fetchCount(db)
            let pending = try Todo.filter(Column("status") == "pending").fetchCount(db)
            return TodoStats(
                total: total,
                completed: completed,
                todayScheduled: todayScheduled,
                todayCompleted: todayCompleted,
                pending: pending
            )
        }
    }
}

public struct TodoStats: Sendable {
    public let total: Int
    public let completed: Int
    public let todayScheduled: Int
    public let todayCompleted: Int
    public let pending: Int

    public var completionRate: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}
