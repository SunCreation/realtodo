import SwiftUI
import RealTodoKit

struct AllTodoView: View {
    var viewModel: TodoListViewModel
    var todayViewModel: TodayViewModel
    @State private var newTodoTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            CategoryFilterView(
                categories: viewModel.categories,
                selectedIds: viewModel.selectedCategoryIds,
                onToggle: { id in viewModel.toggleCategoryFilter(id) }
            )
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    pendingSection
                    scheduledSection
                    completedSection
                }
                .listStyle(.plain)
            }
            actionBar
        }
        .onAppear {
            Task {
                await viewModel.loadAllTodos()
                await viewModel.loadCategories()
            }
        }
    }

    private var pendingSection: some View {
        Group {
            let pending = viewModel.filteredTodos.filter { $0.todo.statusEnum == .pending }
            if !pending.isEmpty {
                Section {
                    HStack {
                        Text("AI 추천 (\(pending.count))")
                            .font(.headline)
                        Spacer()
                        Button("전체 수락") {
                            Task { await viewModel.acceptAllSuggestions(); await todayViewModel.loadTodayTodos() }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        Button("전체 거절") {
                            Task { await viewModel.rejectAllSuggestions() }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                    ForEach(pending) { item in
                        AISuggestionRow(item: item, onAccept: {
                            Task { await viewModel.acceptSuggestion(id: item.todo.id); await todayViewModel.loadTodayTodos() }
                        }, onReject: {
                            Task { await viewModel.dismissTodo(id: item.todo.id) }
                        })
                    }
                }
            }
        }
    }

    private var scheduledSection: some View {
        Group {
            let scheduled = viewModel.filteredTodos.filter { $0.todo.statusEnum == .scheduled }
            if !scheduled.isEmpty {
                Section("오늘 예정") {
                    ForEach(scheduled) { item in
                        TodoRowView(item: item, onToggle: {
                            Task { await viewModel.completeTodo(id: item.todo.id) }
                        }, onMoveToBacklog: {
                            Task { await viewModel.unscheduleTodo(id: item.todo.id) }
                        }, onDelete: {
                            Task { await viewModel.deleteTodo(id: item.todo.id) }
                        })
                    }
                }
            }
        }
    }

    private var completedSection: some View {
        Group {
            let completed = viewModel.filteredTodos.filter { $0.todo.statusEnum == .completed }
            if !completed.isEmpty {
                Section("완료됨") {
                    ForEach(completed) { item in
                        TodoRowView(item: item, onToggle: nil, onMoveToBacklog: nil, onDelete: {
                            Task { await viewModel.deleteTodo(id: item.todo.id) }
                        })
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            TextField("새 할일 추가...", text: $newTodoTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    guard !newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        await viewModel.addTodo(title: newTodoTitle, status: .pending)
                        newTodoTitle = ""
                    }
                }
            Button(action: {
                guard !newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task {
                    await viewModel.addTodo(title: newTodoTitle, status: .pending)
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
}
