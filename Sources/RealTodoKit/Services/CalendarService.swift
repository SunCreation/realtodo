import Foundation

public actor CalendarService {
    public static let shared = CalendarService()

    private init() {}

    public struct GoogleCalendarList: Codable, Sendable {
        public let items: [GoogleCalendar]?
    }

    public struct GoogleCalendar: Codable, Sendable, Identifiable {
        public let id: String
        public let summary: String
        public let primary: Bool?
    }

    public struct GoogleEventList: Codable, Sendable {
        public let items: [GoogleEvent]?
    }

    public struct GoogleEvent: Codable, Sendable, Identifiable {
        public let id: String
        public let summary: String?
        public let start: GoogleEventDateTime?
        public let end: GoogleEventDateTime?
        public let description: String?

        public struct GoogleEventDateTime: Codable, Sendable {
            public let dateTime: String?
            public let date: String?
        }
    }

    public func fetchCalendars(accountId: String) async throws -> [GoogleCalendar] {
        let accessToken = try await AuthService.shared.getValidAccessToken(accountId: accountId)
        var request = URLRequest(url: URL(string: "\(AppConstants.googleCalendarBaseURL)/users/me/calendarList")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw CalendarError.apiError("Failed to fetch calendars: \(body)")
        }
        let list = try JSONDecoder().decode(GoogleCalendarList.self, from: data)
        return list.items ?? []
    }

    public func fetchCalendars() async throws -> [GoogleCalendar] {
        let accounts = try await DatabaseService.shared.fetchAllAccounts()
        guard let account = accounts.first else { throw AuthError.notAuthenticated }
        return try await fetchCalendars(accountId: account.id)
    }

    public func fetchEvents(calendarId: String, accountId: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        let accessToken = try await AuthService.shared.getValidAccessToken(accountId: accountId)
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        var components = URLComponents(string: "\(AppConstants.googleCalendarBaseURL)/calendars/\(calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: df.string(from: from)),
            URLQueryItem(name: "timeMax", value: df.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw CalendarError.apiError("Failed to fetch events: \(body)")
        }
        let list = try JSONDecoder().decode(GoogleEventList.self, from: data)
        return list.items ?? []
    }

    public func fetchEvents(calendarId: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        let accounts = try await DatabaseService.shared.fetchAllAccounts()
        guard let account = accounts.first else { throw AuthError.notAuthenticated }
        return try await fetchEvents(calendarId: calendarId, accountId: account.id, from: from, to: to)
    }

    public func syncAllMappedCalendars() async throws -> [CalendarEvent] {
        let db = DatabaseService.shared
        let accounts = try await db.fetchAllAccounts()
        let mappings = try await db.fetchCalendarMappings()
        var allEvents: [CalendarEvent] = []
        let from = DateHelpers.daysFromNow(-1)
        let to = DateHelpers.daysFromNow(7)
        for account in accounts {
            let accountMappings = mappings.filter { mapping in
                mapping.accountId == account.id || (mapping.accountId == nil && accounts.count == 1)
            }
            for mapping in accountMappings {
                let events = try await fetchEvents(calendarId: mapping.calendarId, accountId: account.id, from: from, to: to)
                let calEvents = events.map { ev -> CalendarEvent in
                    let start = parseEventDate(ev.start)
                    let end = parseEventDate(ev.end)
                    return CalendarEvent(
                        id: "\(account.id)_\(mapping.calendarId)_\(ev.id)",
                        calendarId: mapping.calendarId,
                        calendarName: mapping.calendarName,
                        title: ev.summary,
                        startTime: start,
                        endTime: end,
                        description: ev.description,
                        syncedAt: Date()
                    )
                }
                allEvents.append(contentsOf: calEvents)
            }
        }
        var seenTitles = Set<String>()
        for ev in allEvents {
            let dedupeKey = "\(ev.title ?? "")_\(ev.startTime.map { Int($0.timeIntervalSince1970 / 300) } ?? 0)"
            if seenTitles.contains(dedupeKey) { continue }
            seenTitles.insert(dedupeKey)
            let existing = try await db.fetchTodo(id: "cal_\(ev.id)")
            if existing == nil {
                let mapping = mappings.first { $0.calendarId == ev.calendarId }
                let categoryId = mapping?.categoryId ?? "work"
                let todo = Todo(
                    id: "cal_\(ev.id)",
                    title: ev.title ?? "Untitled event",
                    status: .pending,
                    source: .calendar,
                    parentEventId: ev.id,
                    calendarId: ev.calendarId,
                    dueDate: ev.startTime,
                    aiReason: "Google Calendar에서 자동 등록"
                )
                _ = try await db.createTodo(todo, categoryIds: [categoryId])
            }
        }
        try await db.saveCalendarEvents(allEvents)
        return allEvents
    }

    private func parseEventDate(_ dt: GoogleEvent.GoogleEventDateTime?) -> Date? {
        guard let dt else { return nil }
        if let dateTime = dt.dateTime {
            let formatters: [ISO8601DateFormatter] = {
                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return [f1, f2]
            }()
            for formatter in formatters {
                if let date = formatter.date(from: dateTime) { return date }
            }
            return nil
        }
        if let date = dt.date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: date)
        }
        return nil
    }
}

public enum CalendarError: LocalizedError {
    case apiError(String)
    case noMapping

    public var errorDescription: String? {
        switch self {
        case .apiError(let msg): "Calendar API error: \(msg)"
        case .noMapping: "No calendar mappings configured."
        }
    }
}
