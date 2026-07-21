import SwiftUI
import RealTodoKit

struct PopoverContainerView: View {
    @State private var selectedTab = 0
    @State private var showSettings = false
    var todayVM: TodayViewModel
    var allVM: TodoListViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            TabView(selection: $selectedTab) {
                TodayTodoView(viewModel: todayVM)
                    .tabItem { Label("오늘", systemImage: "sun.max") }
                    .tag(0)
                AllTodoView(viewModel: allVM, todayViewModel: todayVM)
                    .tabItem { Label("전체", systemImage: "tray.full") }
                    .tag(1)
            }
        }
        .frame(width: 360, height: 480)
        .background(.ultraThinMaterial)
        .onAppear {
            Task {
                await todayVM.loadTodayTodos()
                await allVM.loadAllTodos()
                await allVM.loadCategories()
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Text("종료")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text(DateHelpers.displayDateFormatter.string(from: Date()))
                .font(.headline)
            Spacer()
            Button(action: copyCurrentTabTodos) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("할일 목록 복사")
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .popover(isPresented: $showSettings) {
                SettingsView()
                    .frame(minWidth: 480, idealWidth: 520, minHeight: 440, idealHeight: 480)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func copyCurrentTabTodos() {
        let items = selectedTab == 0 ? todayVM.todayTodos : allVM.filteredTodos
        let text = items.map { item -> String in
            let check = item.todo.statusEnum == .completed ? "✅" : "☐"
            let cats = item.categories.map(\.name).joined(separator: ", ")
            let catStr = cats.isEmpty ? "" : " [\(cats)]"
            return "\(check) \(item.todo.title)\(catStr)"
        }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
