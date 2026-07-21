import Foundation
import Observation

@MainActor
@Observable
public final class TodayViewModel {
    public var todayTodos: [TodoWithCategories] = []
    public var isLoading = false
    public var errorMessage: String?

    private let db = DatabaseService.shared

    public init() {}

    public func loadTodayTodos() async {
        isLoading = true
        defer { isLoading = false }
        do {
            todayTodos = try await db.fetchTodayTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addTodo(title: String, categoryIds: [String] = []) async {
        do {
            let todo = Todo(title: title, status: .scheduled, source: .manual, scheduledDate: Date())
            _ = try await db.createTodo(todo, categoryIds: categoryIds)
            await loadTodayTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func completeTodo(id: String) async {
        do {
            try await db.completeTodo(id: id)
            await loadTodayTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func moveToBacklog(id: String) async {
        do {
            try await db.unscheduleTodo(id: id)
            await loadTodayTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setTime(id: String, startMinute: Int?, endMinute: Int?) async {
        do {
            try await db.setTodoTime(id: id, startMinute: startMinute, endMinute: endMinute)
            await loadTodayTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteTodo(id: String) async {
        do {
            try await db.deleteTodo(id: id)
            await loadTodayTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var completedCount: Int {
        todayTodos.filter { $0.todo.statusEnum == .completed }.count
    }

    public var totalCount: Int {
        todayTodos.count
    }

    public var progressText: String {
        "\(completedCount)/\(totalCount)"
    }
}
