import Foundation

public actor TimerService {
    public static let shared = TimerService()

    private var morningSource: DispatchSourceTimer?
    private var periodicSource: DispatchSourceTimer?
    private var morningRoutineHour: Int = AppConstants.defaultMorningRoutineHour
    private var morningRoutineMinute: Int = AppConstants.defaultMorningRoutineMinute
    private var refreshIntervalMinutes: Int = AppConstants.defaultRefreshIntervalMinutes

    private init() {}

    public func start() async {
        await loadSettings()
        try? await runRollover()
        scheduleMorningRoutine()
        schedulePeriodicUpdate()
        if await shouldRunMorningRoutineNow() {
            try? await runMorningRoutine()
        }
    }

    /// Moves yesterday's unfinished "today" todos onto today. Enabled by default;
    /// set the `auto_rollover` setting to "false" to opt out.
    @discardableResult
    public func runRollover() async throws -> Int {
        let db = DatabaseService.shared
        let enabled = (try? await db.getSetting("auto_rollover")) ?? nil
        if enabled == "false" { return 0 }
        return try await db.rolloverUnfinishedTodos(to: Date())
    }

    public func stop() {
        morningSource?.cancel()
        periodicSource?.cancel()
        morningSource = nil
        periodicSource = nil
    }

    public func runMorningRoutine() async throws {
        try? await runRollover()
        let suggestions = try await TaskBreakdownService.shared.runMorningRoutine()
        let db = DatabaseService.shared
        try? await db.setSetting("last_morning_date", value: DateHelpers.isoDateFormatter.string(from: Date()))
        if !suggestions.isEmpty {
            NotificationService.shared.notifyMorningRoutine(count: suggestions.count)
            await updatePendingBadge()
        }
    }

    public func runPeriodicUpdate() async throws {
        let suggestions = try await TaskBreakdownService.shared.runPeriodicUpdate()
        if !suggestions.isEmpty {
            NotificationService.shared.notifyPeriodicUpdate(count: suggestions.count)
            await updatePendingBadge()
        }
    }

    public func updateSettings(hour: Int? = nil, minute: Int? = nil, interval: Int? = nil) async throws {
        if let hour { morningRoutineHour = hour }
        if let minute { morningRoutineMinute = minute }
        if let interval { refreshIntervalMinutes = interval }
        try await saveSettings()
        stop()
        scheduleMorningRoutine()
        schedulePeriodicUpdate()
    }

    public func getSettings() -> TimerSettings {
        TimerSettings(
            morningHour: morningRoutineHour,
            morningMinute: morningRoutineMinute,
            refreshIntervalMinutes: refreshIntervalMinutes
        )
    }

    private func loadSettings() async {
        let db = DatabaseService.shared
        if let hourStr = try? await db.getSetting("morning_hour"),
           let hour = Int(hourStr) {
            morningRoutineHour = hour
        }
        if let minuteStr = try? await db.getSetting("morning_minute"),
           let minute = Int(minuteStr) {
            morningRoutineMinute = minute
        }
        if let intervalStr = try? await db.getSetting("refresh_interval"),
           let interval = Int(intervalStr) {
            refreshIntervalMinutes = interval
        }
    }

    private func saveSettings() async throws {
        let db = DatabaseService.shared
        try await db.setSetting("morning_hour", value: "\(morningRoutineHour)")
        try await db.setSetting("morning_minute", value: "\(morningRoutineMinute)")
        try await db.setSetting("refresh_interval", value: "\(refreshIntervalMinutes)")
    }

    private func scheduleMorningRoutine() {
        morningSource?.cancel()
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = morningRoutineHour
        components.minute = morningRoutineMinute
        guard let target = calendar.date(from: components) else { return }
        var interval = target.timeIntervalSinceNow
        if interval <= 0 { interval += 86400 }

        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: .now() + interval)
        source.setEventHandler { [weak self = self] in
            Task { try? await self?.runMorningRoutine() }
        }
        source.resume()
        morningSource = source
    }

    private func schedulePeriodicUpdate() {
        periodicSource?.cancel()
        guard refreshIntervalMinutes > 0 else { return }

        let interval = TimeInterval(refreshIntervalMinutes * 60)
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler {
            Task { try? await TimerService.shared.runPeriodicUpdate() }
        }
        source.resume()
        periodicSource = source
    }

    private func shouldRunMorningRoutineNow() async -> Bool {
        let db = DatabaseService.shared
        let lastDate = (try? await db.getSetting("last_morning_date")) ?? nil
        let todayStr = DateHelpers.isoDateFormatter.string(from: Date())
        if lastDate == todayStr { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= morningRoutineHour
    }

    private func updatePendingBadge() async {
        do {
            let db = DatabaseService.shared
            let pending = try await db.fetchPendingTodos()
            NotificationService.shared.updateBadgeCount(pending.count)
        } catch {}
    }
}

public struct TimerSettings: Sendable {
    public let morningHour: Int
    public let morningMinute: Int
    public let refreshIntervalMinutes: Int
}
