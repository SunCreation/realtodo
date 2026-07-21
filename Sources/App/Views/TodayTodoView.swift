import SwiftUI
import RealTodoKit

struct TodayTodoView: View {
    var viewModel: TodayViewModel
    @State private var newTodoTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.todayTodos.isEmpty {
                emptyState
            } else {
                todoList
            }
            addBar
        }
        .overlay(alignment: .bottom) {
            if !viewModel.todayTodos.isEmpty {
                progressBar
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("오늘의 할일이 없습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("아래에서 추가하거나 AI 추천을 받아보세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var todoList: some View {
        List {
            ForEach(viewModel.todayTodos.filter { $0.todo.statusEnum != .completed }) { item in
                TodoRowView(item: item, onToggle: {
                    Task { await viewModel.completeTodo(id: item.todo.id) }
                }, onMoveToBacklog: {
                    Task { await viewModel.moveToBacklog(id: item.todo.id) }
                }, onDelete: {
                    Task { await viewModel.deleteTodo(id: item.todo.id) }
                }, onSetTime: { start, end in
                    Task { await viewModel.setTime(id: item.todo.id, startMinute: start, endMinute: end) }
                })
            }
            if viewModel.todayTodos.contains(where: { $0.todo.statusEnum == .completed }) {
                Section("완료됨") {
                    ForEach(viewModel.todayTodos.filter { $0.todo.statusEnum == .completed }) { item in
                        TodoRowView(item: item, onToggle: {
                            Task { await viewModel.moveToBacklog(id: item.todo.id) }
                        }, onMoveToBacklog: nil, onDelete: {
                            Task { await viewModel.deleteTodo(id: item.todo.id) }
                        })
                    }
                }
            }
        }
        .listStyle(.plain)
        .padding(.bottom, 24)
    }

    private var addBar: some View {
        HStack {
            TextField("새 할일 추가...", text: $newTodoTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    guard !newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        await viewModel.addTodo(title: newTodoTitle)
                        newTodoTitle = ""
                    }
                }
            Button(action: {
                guard !newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task {
                    await viewModel.addTodo(title: newTodoTitle)
                    newTodoTitle = ""
                }
            }) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private var progressBar: some View {
        VStack(spacing: 2) {
            ProgressView(value: viewModel.totalCount > 0 ? Double(viewModel.completedCount) / Double(viewModel.totalCount) : 0)
                .tint(.blue)
            Text(viewModel.progressText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(.bar)
    }
}
