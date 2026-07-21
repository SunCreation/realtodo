import Foundation

public enum DateHelpers {
    public static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale.current
        return f
    }()

    public static let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    public static let displayDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    public static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    public static func startOfDay(_ date: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    public static func endOfDay(_ date: Date = Date()) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay(date))!
    }

    public static func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date())!
    }

    public static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    // MARK: - Time of day (minutes from midnight)

    /// Formats minutes-from-midnight (0...1439) as "HH:mm". Returns nil if out of range.
    public static func formatMinutes(_ minutes: Int?) -> String? {
        guard let m = minutes, (0..<1440).contains(m) else { return nil }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Parses "HH:mm" (or "H:mm", "HHmm") into minutes-from-midnight. Returns nil if invalid.
    public static func parseMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts: [String]
        if trimmed.contains(":") {
            parts = trimmed.split(separator: ":").map(String.init)
        } else if trimmed.count == 4, let _ = Int(trimmed) {
            parts = [String(trimmed.prefix(2)), String(trimmed.suffix(2))]
        } else {
            return nil
        }
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}
