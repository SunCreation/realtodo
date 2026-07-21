import Foundation

public enum OutputFormatter {
    public enum Format: String {
        case table
        case json
    }

    public static func formatTodos(_ todos: [TodoWithCategories], format: Format) -> String {
        switch format {
        case .json: formatTodosJSON(todos)
        case .table: formatTodosTable(todos)
        }
    }

    public static func formatTodayJSON(_ todos: [TodoWithCategories]) -> String {
        let completed = todos.filter { $0.todo.statusEnum == .completed }.count
        let dict: [String: Any] = [
            "date": DateHelpers.isoDateFormatter.string(from: Date()),
            "stats": [
                "total": todos.count,
                "completed": completed,
            ],
            "todos": todos.map { item -> [String: Any] in
                var d: [String: Any] = [
                    "id": item.todo.id,
                    "title": item.todo.title,
                    "status": item.todo.status,
                    "source": item.todo.source,
                    "categories": item.categories.map(\.name),
                ]
                if let p = item.todo.priority { d["priority"] = p }
                if let r = item.todo.aiReason { d["aiReason"] = r }
                if let tl = item.todo.timeRangeLabel { d["time"] = tl }
                return d
            },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func formatStats(_ stats: TodoStats, format: Format) -> String {
        switch format {
        case .json:
            let dict: [String: Any] = [
                "total": stats.total,
                "completed": stats.completed,
                "todayScheduled": stats.todayScheduled,
                "todayCompleted": stats.todayCompleted,
                "pending": stats.pending,
                "completionRate": String(format: "%.1f%%", stats.completionRate * 100),
            ]
            let data = try! JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        case .table:
            return """
            전체: \(stats.total) | 완료: \(stats.completed) | 진행률: \(String(format: "%.1f%%", stats.completionRate * 100))
            오늘 예정: \(stats.todayScheduled) | 오늘 완료: \(stats.todayCompleted)
            대기(AI): \(stats.pending)
            """
        }
    }

    public static func formatTodoDetail(_ item: TodoWithCategories, subtasks: [TodoWithCategories] = []) -> String {
        let t = item.todo
        var lines: [String] = []
        lines.append("ID: \(t.id)")
        lines.append("제목: \(t.title)")
        if let desc = t.todoDescription { lines.append("설명: \(desc)") }
        lines.append("상태: \(statusLabel(t.statusEnum))")
        if let p = t.priorityEnum { lines.append("우선순위: \(p.rawValue)") }
        lines.append("출처: \(t.sourceEnum.rawValue)")
        if !item.categories.isEmpty {
            lines.append("카테고리: \(item.categories.map(\.name).joined(separator: ", "))")
        }
        if let d = t.dueDate { lines.append("마감일: \(DateHelpers.displayDateTimeFormatter.string(from: d))") }
        if let d = t.scheduledDate { lines.append("예정일: \(DateHelpers.isoDateFormatter.string(from: d))") }
        if let tl = t.timeRangeLabel { lines.append("시간대: \(tl)") }
        if let reason = t.aiReason { lines.append("AI 이유: \(reason)") }
        if !subtasks.isEmpty {
            lines.append("")
            lines.append("하위 태스크:")
            for sub in subtasks {
                let check = sub.todo.statusEnum == .completed ? "✅" : "☐"
                lines.append("  \(check) \(sub.todo.title)")
            }
        }
        lines.append("생성: \(DateHelpers.displayDateTimeFormatter.string(from: t.createdAt))")
        return lines.joined(separator: "\n")
    }

    private static func formatTodosTable(_ todos: [TodoWithCategories]) -> String {
        if todos.isEmpty { return "할일이 없습니다." }
        var lines: [String] = []
        for (i, item) in todos.enumerated() {
            let t = item.todo
            let check = t.statusEnum == .completed ? "✅" : "☐"
            let cats = item.categories.map { cat in
                "\(cat.name) \(colorDot(cat.color))"
            }.joined(separator: " ")
            let priority = t.priorityEnum.map { "[\($0.rawValue)]" } ?? ""
            let time = t.timeRangeLabel.map { "\($0)  " } ?? ""
            let line = "  \(check) \(i + 1). \(time)\(t.title)\t\(cats)\t\(priority)"
            lines.append(line)
        }
        let completed = todos.filter { $0.todo.statusEnum == .completed }.count
        lines.append("")
        lines.append("  진행률: \(completed)/\(todos.count) (\(todos.count > 0 ? String(format: "%.0f%%", Double(completed) / Double(todos.count) * 100) : "0%"))")
        return lines.joined(separator: "\n")
    }

    private static func formatTodosJSON(_ todos: [TodoWithCategories]) -> String {
        let arr = todos.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "id": item.todo.id,
                "title": item.todo.title,
                "status": item.todo.status,
                "source": item.todo.source,
                "categories": item.categories.map(\.name),
                "createdAt": DateHelpers.iso8601Formatter.string(from: item.todo.createdAt),
            ]
            if let p = item.todo.priority { dict["priority"] = p }
            if let d = item.todo.dueDate { dict["dueDate"] = DateHelpers.iso8601Formatter.string(from: d) }
            if let d = item.todo.scheduledDate { dict["scheduledDate"] = DateHelpers.iso8601Formatter.string(from: d) }
            if let r = item.todo.aiReason { dict["aiReason"] = r }
            return dict
        }
        let data = (try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func statusLabel(_ status: TodoStatus) -> String {
        switch status {
        case .pending: "대기"
        case .scheduled: "오늘"
        case .inProgress: "진행중"
        case .completed: "완료"
        case .dismissed: "거절됨"
        }
    }

    public static func colorDot(_ hex: String) -> String {
        switch hex.lowercased() {
        case "#3b82f6": "🔵"
        case "#22c55e": "🟢"
        case "#f59e0b": "🟡"
        case "#ef4444": "🔴"
        case "#8b5cf6": "🟣"
        default: "⚪"
        }
    }
}
