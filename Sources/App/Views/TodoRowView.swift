import SwiftUI
import RealTodoKit

struct TodoRowView: View {
    let item: TodoWithCategories
    let onToggle: (() -> Void)?
    let onMoveToBacklog: (() -> Void)?
    let onDelete: (() -> Void)?
    var onSetTime: ((Int?, Int?) -> Void)? = nil

    @State private var isExpanded = false
    @State private var showTimeEditor = false
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var useEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                toggleButton
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    if let reason = item.todo.aiReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                categoryDots
                statusBadge
                sourceIcon
            }
            if isExpanded {
                SubtaskView(parentId: item.todo.id)
            }
        }
        .contextMenu { contextMenuContent }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation { isExpanded.toggle() }
        }
        .popover(isPresented: $showTimeEditor) { timeEditor }
    }

    private var timeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("시간대 배정").font(.headline)
            DatePicker("시작", selection: $editStart, displayedComponents: .hourAndMinute)
            Toggle("종료 시간 사용", isOn: $useEnd)
            if useEnd {
                DatePicker("종료", selection: $editEnd, displayedComponents: .hourAndMinute)
            }
            Divider()
            HStack {
                Button("지우기") {
                    onSetTime?(nil, nil)
                    showTimeEditor = false
                }
                Spacer()
                Button("저장") {
                    let start = Self.minutes(from: editStart)
                    let end = useEnd ? Self.minutes(from: editEnd) : nil
                    onSetTime?(start, end)
                    showTimeEditor = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private func prepareTimeEditor() {
        let base = Self.date(fromMinutes: item.todo.startMinute) ?? Date()
        editStart = base
        if let end = Self.date(fromMinutes: item.todo.endMinute) {
            editEnd = end
            useEnd = true
        } else {
            editEnd = base
            useEnd = false
        }
    }

    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func date(fromMinutes minutes: Int?) -> Date? {
        guard let m = minutes else { return nil }
        return Calendar.current.date(
            bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()
        )
    }

    private var toggleButton: some View {
        Button(action: { onToggle?() }) {
            Image(systemName: item.todo.statusEnum == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(item.todo.statusEnum == .completed ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var titleRow: some View {
        HStack(spacing: 4) {
            if let timeLabel = item.todo.timeRangeLabel {
                Text(timeLabel)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
                    .foregroundStyle(.blue)
            }
            Text(item.todo.title)
                .strikethrough(item.todo.statusEnum == .completed)
                .foregroundStyle(item.todo.statusEnum == .completed ? .secondary : .primary)
            if let priority = item.todo.priorityEnum {
                priorityBadge(priority)
            }
        }
    }

    private func priorityBadge(_ priority: Priority) -> some View {
        Text(priority.rawValue)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(priorityColor(priority).opacity(0.2))
            .cornerRadius(4)
            .foregroundStyle(priorityColor(priority))
    }

    private func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        }
    }

    private var categoryDots: some View {
        HStack(spacing: 2) {
            ForEach(item.categories) { cat in
                Circle()
                    .fill(Color(hex: cat.color) ?? .gray)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var statusBadge: some View {
        Group {
            switch item.todo.statusEnum {
            case .pending:
                Text("대기")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundStyle(.orange)
            case .inProgress:
                Text("진행중")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundStyle(.blue)
            default:
                EmptyView()
            }
        }
    }

    private var sourceIcon: some View {
        Group {
            switch item.todo.sourceEnum {
            case .calendar:
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
            case .aiSuggested:
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            case .manual:
                EmptyView()
            }
        }
        .font(.caption)
    }

    private var contextMenuContent: some View {
        Group {
            if let onToggle {
                Button(item.todo.statusEnum == .completed ? "완료 취소" : "완료") { onToggle() }
            }
            if let onMoveToBacklog {
                Button("전체 할일로 이동") { onMoveToBacklog() }
            }
            if onSetTime != nil {
                Button(item.todo.timeRangeLabel == nil ? "시간대 배정" : "시간대 변경") {
                    prepareTimeEditor()
                    showTimeEditor = true
                }
            }
            Button("클립보드에 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.todo.title, forType: .string)
            }
            Button("태스크 분해") {
                Task {
                    let breakdown = TaskBreakdownService.shared
                    _ = try? await breakdown.breakdownTodo(todoId: item.todo.id)
                }
            }
            Divider()
            if let onDelete {
                Button("삭제", role: .destructive) { onDelete() }
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6 else { return nil }
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
