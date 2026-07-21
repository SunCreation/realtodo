import SwiftUI
import RealTodoKit

struct SubtaskView: View {
    let parentId: String
    @State private var subtasks: [TodoWithCategories] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                ForEach(subtasks) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.todo.statusEnum == .completed ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(item.todo.statusEnum == .completed ? .green : .secondary)
                        Text(item.todo.title)
                            .font(.caption)
                            .strikethrough(item.todo.statusEnum == .completed)
                            .foregroundStyle(item.todo.statusEnum == .completed ? .secondary : .primary)
                    }
                }
            }
        }
        .padding(.leading, 24)
        .onAppear {
            Task {
                isLoading = true
                subtasks = (try? await DatabaseService.shared.fetchSubtasks(parentTodoId: parentId)) ?? []
                isLoading = false
            }
        }
    }
}
