import SwiftUI
import RealTodoKit

struct AddTodoView: View {
    let viewModel: TodoListViewModel
    @State private var title = ""
    @State private var selectedCategoryIds: Set<String> = []
    @State private var priority: Priority? = nil
    @State private var status: TodoStatus = .scheduled
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            TextField("할일 제목", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("카테고리:")
                ForEach(viewModel.categories) { cat in
                    Toggle(cat.name, isOn: Binding(
                        get: { selectedCategoryIds.contains(cat.id) },
                        set: { on in
                            if on { selectedCategoryIds.insert(cat.id) }
                            else { selectedCategoryIds.remove(cat.id) }
                        }
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Text("우선순위:")
                Picker("", selection: $priority) {
                    Text("없음").tag(nil as Priority?)
                    ForEach(Priority.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p as Priority?)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("추가") {
                    Task {
                        await viewModel.addTodo(
                            title: title,
                            categoryIds: Array(selectedCategoryIds),
                            status: status
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
