import Foundation

public enum AppConstants {
    public static let appName = "RealTodo"
    public static let databaseName = "realtodo.db"
    public static let cliName = "real_todo"

    public static var databasePath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.path
        let dir = (appSupport as NSString).appendingPathComponent(appName)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent(databaseName)
    }

    public static let googleCredentialsPath = NSHomeDirectory() + "/.config/mcp-google/credentials.json"

    public static let googleOAuthBaseURL = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let googleTokenURL = "https://oauth2.googleapis.com/token"
    public static let googleCalendarBaseURL = "https://www.googleapis.com/calendar/v3"
    public static let googleRedirectURI = "http://localhost"
    public static let googleScopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
    ]
    public static let googleOAuthPromptMode = "select_account"

    public static let agyPath = NSHomeDirectory() + "/.local/bin/agy"
    public static let defaultMorningRoutineHour = 8
    public static let defaultMorningRoutineMinute = 0
    public static let defaultRefreshIntervalMinutes = 30

    public static let defaultCategories: [(id: String, name: String, color: String, sortOrder: Int)] = [
        ("work", "업무", "#3B82F6", 0),
        ("personal", "개인", "#22C55E", 1),
    ]
}
