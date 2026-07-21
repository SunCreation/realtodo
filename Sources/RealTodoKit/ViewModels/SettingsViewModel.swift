import Foundation
import Observation
import AppKit

public struct AccountCalendar: Identifiable, Sendable {
    public let accountId: String
    public let accountEmail: String
    public let calendar: CalendarService.GoogleCalendar

    public var id: String { "\(accountId)::\(calendar.id)" }
}

public struct AccountCalendarMapping: Identifiable, Sendable {
    public let accountId: String?
    public let calendarId: String
    public let calendarName: String
    public let categoryId: String

    public var id: String { "\(accountId ?? "legacy")::\(calendarId)" }
}

@MainActor
@Observable
public final class SettingsViewModel {
    public var categories: [Category] = []
    public var accounts: [GoogleAccount] = []
    public var calendarMappings: [AccountCalendarMapping] = []
    public var availableCalendars: [AccountCalendar] = []
    public var timerSettings: TimerSettings?
    public var isLoading = false
    public var errorMessage: String?
    public var newCategoryName = ""
    public var newCategoryColor = "#F59E0B"
    public var isAuthenticating = false

    private let db = DatabaseService.shared
    private var oauthServer: OAuthCallbackServer?

    public init() {}

    public var isCalendarAuthenticated: Bool { !accounts.isEmpty }

    public func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        await loadCategories()
        await loadCalendarMappings()
        await loadTimerSettings()
        await loadAccounts()
        if isCalendarAuthenticated {
            await fetchAvailableCalendars()
        }
    }

    public func loadCategories() async {
        do {
            categories = try await db.fetchAllCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addCategory(name: String, color: String) async {
        do {
            let cat = Category(name: name, color: color, sortOrder: categories.count)
            _ = try await db.createCategory(cat)
            await loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteCategory(id: String) async {
        do {
            try await db.deleteCategory(id: id)
            await loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadCalendarMappings() async {
        do {
            calendarMappings = try await db.fetchCalendarMappings().map { m in
                AccountCalendarMapping(
                    accountId: m.accountId,
                    calendarId: m.calendarId,
                    calendarName: m.calendarName,
                    categoryId: m.categoryId
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadAccounts() async {
        do {
            accounts = try await db.fetchAllAccounts()
        } catch {
            accounts = []
            errorMessage = error.localizedDescription
        }
    }

    public func fetchAvailableCalendars() async {
        do {
            var calendars: [AccountCalendar] = []
            let currentAccounts = accounts.isEmpty ? try await db.fetchAllAccounts() : accounts
            for account in currentAccounts {
                let fetched = try await CalendarService.shared.fetchCalendars(accountId: account.id)
                calendars.append(contentsOf: fetched.map {
                    AccountCalendar(accountId: account.id, accountEmail: account.email, calendar: $0)
                })
            }
            availableCalendars = calendars
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func mapCalendar(accountId: String?, calendarId: String, calendarName: String, categoryId: String) async {
        do {
            try await db.setCalendarMapping(accountId: accountId, calendarId: calendarId, calendarName: calendarName, categoryId: categoryId)
            await loadCalendarMappings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func unmapCalendar(accountId: String?, calendarId: String) async {
        do {
            try await db.removeCalendarMapping(accountId: accountId, calendarId: calendarId)
            await loadCalendarMappings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func syncCalendar() async {
        do {
            _ = try await CalendarService.shared.syncAllMappedCalendars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadTimerSettings() async {
        timerSettings = await TimerService.shared.getSettings()
    }

    public func updateTimerSettings(hour: Int? = nil, minute: Int? = nil, interval: Int? = nil) async {
        do {
            try await TimerService.shared.updateSettings(hour: hour, minute: minute, interval: interval)
            await loadTimerSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runMorningRoutineNow() async {
        do {
            _ = try await TaskBreakdownService.shared.runMorningRoutine()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func signInWithGoogle() async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let creds = try await AuthService.shared.loadCredentials()
            let port: UInt16 = 9876
            let redirectURI = "http://localhost:\(port)"

            let server = OAuthCallbackServer(port: port)
            guard server != nil else {
                errorMessage = "로컬 서버를 시작할 수 없습니다 (포트 \(port))."
                return
            }
            self.oauthServer = server

            guard let serverRef = oauthServer else {
                oauthServer = nil
                errorMessage = "로컬 서버를 시작할 수 없습니다 (포트 \(port))."
                return
            }

            let authURL = await AuthService.shared.buildAuthURL(
                clientId: creds.installed.clientId,
                redirectURI: redirectURI
            )
            NSWorkspace.shared.open(authURL)

            guard let callbackURL = await serverRef.waitForCallback(timeout: 180) else {
                oauthServer = nil
                errorMessage = "인증 시간이 초과되었습니다. 다시 시도해주세요."
                return
            }
            oauthServer = nil

            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                let errorDesc = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "error" })?.value ?? "unknown"
                errorMessage = "인증 실패: \(errorDesc)"
                return
            }

            let account = try await AuthService.shared.exchangeAndSaveAccount(code: code, redirectURI: redirectURI)
            errorMessage = nil
            await loadAccounts()
            let fetched = try await CalendarService.shared.fetchCalendars(accountId: account.id)
            availableCalendars.removeAll { $0.accountId == account.id }
            availableCalendars.append(contentsOf: fetched.map {
                AccountCalendar(accountId: account.id, accountEmail: account.email, calendar: $0)
            })
            await loadCalendarMappings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func removeAccount(id: String) async {
        do {
            try await db.deleteAccount(id: id)
            accounts.removeAll { $0.id == id }
            availableCalendars.removeAll { $0.accountId == id }
            await loadCalendarMappings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

final class OAuthCallbackServer {
    private var serverSocket: Int32 = -1
    private let queue = DispatchQueue(label: "oauth-callback-server")
    private var continuation: CheckedContinuation<URL?, Never>?
    private var timedOut = false

    init?(port: UInt16) {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_PASSIVE

        var address: UnsafeMutablePointer<addrinfo>?
        let portStr = "\(port)"
        guard getaddrinfo(nil, portStr, &hints, &address) == 0, let addr = address else {
            return nil
        }
        defer { freeaddrinfo(address) }

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock != -1 else { return nil }

        var opt: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout.size(ofValue: opt)))

        guard bind(sock, addr.pointee.ai_addr, addr.pointee.ai_addrlen) == 0,
              listen(sock, 1) == 0 else {
            close(sock)
            return nil
        }

        serverSocket = sock
        startListening(port: port)
    }

    private func startListening(port: UInt16) {
        let sock = serverSocket
        queue.async { [weak self] in
            guard let self, sock >= 0 else { return }
            let client = accept(sock, nil, nil)
            guard client >= 0 else { return }

            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = recv(client, &buffer, buffer.count, 0)
            guard bytesRead > 0 else { close(client); return }

            let request = String(bytes: buffer[..<bytesRead], encoding: .ascii) ?? ""
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let path = firstLine.components(separatedBy: " ").dropFirst().first ?? "/"

            let successHTML = """
            HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\
            <html><body style="display:flex;justify-content:center;align-items:center;height:100vh;\
            font-family:system-ui;background:#f0f0f0">\
            <div style="text-align:center;padding:40px;background:white;border-radius:16px;box-shadow:0 2px 8px rgba(0,0,0,0.1)">\
            <h1 style="color:#22C55E">✅ 인증 완료</h1>\
            <p style="color:#666">RealTodo로 돌아가세요. 이 탭은 닫으셔도 됩니다.</p></div></body></html>
            """
            let data = successHTML.data(using: .utf8)!
            _ = data.withUnsafeBytes { ptr in
                send(client, ptr.baseAddress, data.count, 0)
            }
            close(client)

            if let fullURL = URL(string: "http://localhost:\(port)\(path)") {
                DispatchQueue.main.async {
                    self.continuation?.resume(returning: fullURL)
                    self.continuation = nil
                }
            }
        }
    }

    func waitForCallback(timeout: TimeInterval) async -> URL? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                if self.continuation != nil {
                    self.timedOut = true
                    self.continuation?.resume(returning: nil)
                    self.continuation = nil
                }
            }
        }
    }

    func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    deinit { stop() }
}
