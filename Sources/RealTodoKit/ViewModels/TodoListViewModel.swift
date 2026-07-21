import Foundation
import Observation

@MainActor
@Observable
public final class TodoListViewModel {
    public var todos: [TodoWithCategories] = []
    public var categories: [Category] = []
    public var selectedCategoryIds: Set<String> = []
    public var isLoading = false
    public var errorMessage: String?

    private let db = DatabaseService.shared

    public init() {}

    public func loadCategories() async {
        do {
            categories = try await db.fetchAllCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadAllTodos() async {
        isLoading = true
        defer { isLoading = false }
        do {
            todos = try await db.fetchAllTodos(status: nil, categoryIds: [])
            if !selectedCategoryIds.isEmpty {
                todos = todos.filter { item in
                    item.categories.contains { selectedCategoryIds.contains($0.id) }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addTodo(title: String, categoryIds: [String] = [], status: TodoStatus = .pending) async {
        do {
            let todo = Todo(title: title, status: status, source: .manual)
            _ = try await db.createTodo(todo, categoryIds: categoryIds)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteTodo(id: String) async {
        do {
            try await db.deleteTodo(id: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func completeTodo(id: String) async {
        do {
            try await db.completeTodo(id: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func scheduleTodo(id: String) async {
        do {
            try await db.scheduleTodo(id: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func unscheduleTodo(id: String) async {
        do {
            try await db.unscheduleTodo(id: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func dismissTodo(id: String) async {
        do {
            try await db.dismissTodo(id: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func acceptSuggestion(id: String) async {
        do {
            try await db.scheduleTodo(id: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func acceptAllSuggestions() async {
        do {
            _ = try await TaskBreakdownService.shared.acceptAllSuggestions()
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func rejectAllSuggestions() async {
        do {
            _ = try await TaskBreakdownService.shared.rejectAllSuggestions()
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func breakdownTodo(id: String) async {
        do {
            _ = try await TaskBreakdownService.shared.breakdownTodo(todoId: id)
            await loadAllTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleCategoryFilter(_ categoryId: String) {
        if selectedCategoryIds.contains(categoryId) {
            selectedCategoryIds.remove(categoryId)
        } else {
            selectedCategoryIds.insert(categoryId)
        }
    }

    public var filteredTodos: [TodoWithCategories] {
        if selectedCategoryIds.isEmpty { return todos }
        return todos.filter { item in
            item.categories.contains { selectedCategoryIds.contains($0.id) }
        }
    }
}
