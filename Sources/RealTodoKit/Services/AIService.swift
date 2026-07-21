import Foundation

public struct AIContext: Sendable {
    public struct CalendarEventInfo: Encodable, Sendable {
        public let title: String?
        public let start: String?
        public let end: String?
        public let calendar: String?
    }

    public struct TodoInfo: Encodable, Sendable {
        public let id: String
        public let title: String
        public let status: String
        public let priority: String?
        public let categories: String
        public let source: String
        public let aiReason: String?
        public let created: String?
    }

    public let date: String
    public let time: String
    public let events: [CalendarEventInfo]
    public let scheduledToday: [TodoInfo]
    public let completedToday: [TodoInfo]
    public let pendingSuggestions: [TodoInfo]
    public let recentlyDismissed: [TodoInfo]
    public let allActiveTitles: [String]
}

public actor AIService {
    public static let shared = AIService()

    private let processQueue = DispatchQueue(label: "com.realtodo.aiservice", qos: .userInitiated)

    private init() {}

    public func breakdownTask(_ todo: TodoWithCategories) async throws -> [AISuggestion] {
        let prompt = buildBreakdownPrompt(todo: todo)
        return try await callAgy(prompt: prompt)
    }

    /// Review pass: agy inspects current pending AI suggestions (with ids) and
    /// returns CRUD actions — delete stale ones, update wording/priority, create
    /// new ones. Returns an empty array if agy produced nothing actionable.
    public func reviewSuggestions(context: AIContext, mode: ReviewMode) async throws -> [AIAction] {
        let prompt = buildReviewPrompt(context: context, mode: mode)
        return try await callAgyActions(prompt: prompt)
    }

    public enum ReviewMode: Sendable {
        case morning
        case periodic
    }

    private func buildBreakdownPrompt(todo: TodoWithCategories) -> String {
        return """
        다음 할일을 실행 가능한 소규모 태스크로 분해해주세요:
        제목: \(todo.todo.title)
        설명: \(todo.todo.todoDescription ?? "없음")
        카테고리: \(todo.categories.map(\.name).joined(separator: ", "))

        반드시 아래 JSON 형식만 출력 (다른 텍스트 없이):
        [
          {
            "title": "소규모 태스크 제목",
            "categories": ["work"],
            "reason": "이 태스크가 필요한 이유",
            "priority": "medium"
          }
        ]
        """
    }

    private func buildReviewPrompt(context: AIContext, mode: ReviewMode) -> String {
        let eventsJSON = encodeForPrompt(context.events)
        let scheduledJSON = encodeForPrompt(context.scheduledToday)
        let completedJSON = encodeForPrompt(context.completedToday)
        let pendingJSON = encodeForPrompt(context.pendingSuggestions)
        let dismissedJSON = encodeForPrompt(context.recentlyDismissed)
        let allTitlesJSON = encodeForPrompt(context.allActiveTitles.map { ["title": $0] })

        let modeLine = mode == .morning
            ? "지금은 하루 시작입니다. 오늘 하루 전체를 기준으로 추천을 정리하세요."
            : "지금은 하루 중 주기적 점검입니다. 시간이 지나 무의미해진 추천을 정리하고 꼭 필요한 것만 보강하세요."

        return """
        당신은 개인 비서입니다. 기존 AI 추천 목록을 **검토**해서 직접 정리(CRUD)합니다.
        \(modeLine)

        ## 현재 상황
        - 날짜/시간: \(context.date) \(context.time)
        - 캘린더 일정: \(eventsJSON)

        ## 사용자 할일 상태
        - 오늘 예정(사용자 수락): \(scheduledJSON)
        - 오늘 완료: \(completedJSON)
        - 사용자가 거절한 추천: \(dismissedJSON)
        - 등록된 모든 할일 제목 (중복 금지): \(allTitlesJSON)

        ## 검토 대상 (오직 이 항목들만 update/delete 가능, id 사용)
        \(pendingJSON)

        ## 수행할 작업 (action 배열로 출력)
        1. **delete**: 시간이 지나 무의미한 추천(이미 끝난 일정 기반, 오늘과 무관, 너무 오래된 created), 거절 패턴과 겹치는 것 → `{"action":"delete","id":"해당 id"}`
        2. **update**: 제목이 모호하거나 우선순위가 잘못된 추천 개선 → `{"action":"update","id":"해당 id","title":"개선된 제목","priority":"high|medium|low","reason":"이유"}`
        3. **create**: 일정 기반으로 새로 필요한 구체적 할일 → `{"action":"create","title":"구체적 실행 내용","categories":["work"],"reason":"왜 필요한지","priority":"medium"}`

        ## 규칙
        - update/delete의 id는 반드시 "검토 대상" 목록의 id만 사용 (예정/완료/수동 항목은 건드리지 마세요)
        - 중복 생성 금지: 등록된 제목과 유사하면 create 하지 마세요
        - 양보다 질. 바꿀 게 없으면 빈 배열 []
        - 카테고리: "work" 또는 "personal"

        ## 출력 (JSON 배열만, 다른 텍스트 없이)
        ```json
        [
          {"action":"delete","id":"..."},
          {"action":"update","id":"...","title":"...","priority":"high","reason":"..."},
          {"action":"create","title":"...","categories":["work"],"reason":"...","priority":"medium"}
        ]
        ```
        """
    }

    private func callAgy(prompt: String) async throws -> [AISuggestion] {
        guard let raw = await runAgyRaw(prompt: prompt) else {
            throw AIError.executionFailed("agy did not produce output")
        }
        let result = Self.parseAIResponse(raw)
        if result.isEmpty {
            throw AIError.parseError("AI returned no valid suggestions")
        }
        return result
    }

    private func callAgyActions(prompt: String) async throws -> [AIAction] {
        // Reviews reason over the full pending backlog, so allow a longer window.
        guard let raw = await runAgyRaw(prompt: prompt, timeout: 180) else {
            throw AIError.executionFailed("agy did not produce output")
        }
        // An empty action list is a valid "nothing to change" result.
        return Self.parseActions(raw)
    }

    private func runAgyRaw(prompt: String, timeout: TimeInterval = 60) async -> String? {
        await withCheckedContinuation { continuation in
            processQueue.async {
                continuation.resume(returning: Self.runAgyProcess(prompt: prompt, timeout: timeout))
            }
        }
    }

    /// Runs `agy --print` and returns raw stdout, or nil on launch/timeout failure.
    ///
    /// Only *launch* failures are retried (they fail instantly, so a retry is
    /// cheap). A timeout is not retried: the process already consumed the full
    /// window, so retrying would silently double the user-visible wait.
    private static func runAgyProcess(prompt: String, timeout: TimeInterval = 60, attempt: Int = 0) -> String? {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: AppConstants.agyPath)
        process.arguments = ["--print", prompt]
        process.standardOutput = pipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            logAgyFailure("launch failed (\(error.localizedDescription)) — path: \(AppConstants.agyPath)")
            if attempt == 0 { return runAgyProcess(prompt: prompt, timeout: timeout, attempt: 1) }
            return nil
        }
        // Drain stdout/stderr concurrently on background queues. agy can emit
        // more than the OS pipe buffer (~64KB); reading only after exit would
        // block the child on a full pipe and force a spurious timeout.
        var outputData = Data()
        var errorData = Data()
        let drainGroup = DispatchGroup()
        let drainQueue = DispatchQueue(label: "agy.drain", attributes: .concurrent)
        drainQueue.async(group: drainGroup) {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        }
        drainQueue.async(group: drainGroup) {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let timeoutDeadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < timeoutDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if process.isRunning {
            process.terminate()                  // closes write ends → drains hit EOF
            drainGroup.wait()
            logAgyFailure("timed out after \(Int(timeout))s\(stderrDetail(errorData))")
            return nil
        }
        process.waitUntilExit()
        drainGroup.wait()
        guard process.terminationStatus == 0 else {
            logAgyFailure("exited with status \(process.terminationStatus)\(stderrDetail(errorData))")
            return nil
        }
        return String(data: outputData, encoding: .utf8)
    }

    /// Formats captured stderr for a failure log, trimmed to keep the line readable.
    private static func stderrDetail(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return "" }
        let clipped = text.count > 500 ? String(text.prefix(500)) + "…" : text
        return " — stderr: \(clipped)"
    }

    /// Surfaces agy failures on stderr so they are visible in the CLI and logs,
    /// instead of collapsing every failure into an opaque nil.
    private static func logAgyFailure(_ message: String) {
        FileHandle.standardError.write(Data("[AIService] agy \(message)\n".utf8))
    }

    public static func parseAIResponse(_ output: String) -> [AISuggestion] {
        guard let jsonString = extractJSON(from: output) else { return [] }
        guard let data = jsonString.data(using: .utf8) else { return [] }

        if let suggestions = try? JSONDecoder().decode([AISuggestion].self, from: data) {
            return suggestions
        }
        if let wrapper = try? JSONDecoder().decode(AIBreakdownResponse.self, from: data) {
            return wrapper.tasks
        }
        if let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return rawArray.compactMap { dict -> AISuggestion? in
                guard let title = dict["title"] as? String else { return nil }
                let cats = (dict["categories"] as? [String]) ??
                           (dict["category"] as? String).map { [$0] } ?? []
                var parsedSubtasks: [AISubtask]? = nil
                if let rawSubs = dict["subtasks"] as? [[String: Any]] {
                    parsedSubtasks = rawSubs.compactMap { sub -> AISubtask? in
                        guard let t = sub["title"] as? String else { return nil }
                        return AISubtask(title: t, reason: sub["reason"] as? String)
                    }
                }
                return AISuggestion(
                    title: title,
                    categories: cats,
                    parentEventId: dict["parentEventId"] as? String ?? dict["parent_event_id"] as? String,
                    parentTodoId: dict["parentTodoId"] as? String ?? dict["parent_todo_id"] as? String,
                    reason: dict["reason"] as? String ?? "",
                    priority: dict["priority"] as? String,
                    subtasks: parsedSubtasks
                )
            }
        }
        return []
    }

    public static func parseActions(_ output: String) -> [AIAction] {
        guard let jsonString = extractJSON(from: output),
              let data = jsonString.data(using: .utf8) else { return [] }

        if let actions = try? JSONDecoder().decode([AIAction].self, from: data) {
            return actions
        }
        if let wrapper = try? JSONDecoder().decode(AIActionResponse.self, from: data) {
            return wrapper.actions
        }
        if let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return rawArray.compactMap { AIAction(dict: $0) }
        }
        if let single = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = single["actions"] as? [[String: Any]] {
            return arr.compactMap { AIAction(dict: $0) }
        }
        return []
    }

    private static func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "[") ?? text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        for i in text.indices[start...] {
            let char = text[i]
            if escape { escape = false; continue }
            if char == "\\" { escape = true; continue }
            if char == "\"" { inString.toggle(); continue }
            if inString { continue }
            if char == "[" || char == "{" { depth += 1 }
            if char == "]" || char == "}" { depth -= 1 }
            if depth == 0 { return String(text[start...i]) }
        }
        return nil
    }

    private func encodeForPrompt<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

public enum AIError: LocalizedError {
    case executionFailed(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let msg): "AI execution failed: \(msg)"
        case .parseError(let msg): "AI response parse error: \(msg)"
        }
    }
}
