import Foundation

public struct GoogleCredentials: Codable, Sendable {
    public struct Installed: Codable, Sendable {
        public let clientId: String
        public let clientSecret: String
        public let redirectUris: [String]

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case redirectUris = "redirect_uris"
        }
    }
    public let installed: Installed
}

public struct GoogleTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let tokenType: String
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
    }
}

public struct SavedToken: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expirationDate: Date
    public let scope: String?

    public var isExpired: Bool { Date() >= expirationDate }
}

public struct GoogleUserInfo: Codable, Sendable {
    public let email: String
    public let name: String?
}

public actor AuthService {
    public static let shared = AuthService()

    private var credentials: GoogleCredentials?

    private init() {}

    public func loadCredentials() throws -> GoogleCredentials {
        if let credentials { return credentials }
        let data = try Data(contentsOf: URL(fileURLWithPath: AppConstants.googleCredentialsPath))
        let creds = try JSONDecoder().decode(GoogleCredentials.self, from: data)
        self.credentials = creds
        return creds
    }

    public func getValidAccessToken(accountId: String) async throws -> String {
        let db = DatabaseService.shared
        guard var account = try await db.fetchAccount(id: accountId) else {
            throw AuthError.notAuthenticated
        }
        if !account.isExpired {
            return account.accessToken
        }
        guard let refreshToken = account.refreshToken else {
            throw AuthError.noRefreshToken
        }
        let creds = try loadCredentials()
        let newToken = try await refreshAccessToken(
            refreshToken: refreshToken,
            clientId: creds.installed.clientId,
            clientSecret: creds.installed.clientSecret
        )
        account.accessToken = newToken.accessToken
        account.refreshToken = newToken.refreshToken ?? account.refreshToken
        account.expirationDate = newToken.expirationDate
        account.scope = newToken.scope ?? account.scope
        try await db.updateAccount(account)
        return account.accessToken
    }

    public func getValidAccessToken() async throws -> String {
        let accounts = try await DatabaseService.shared.fetchAllAccounts()
        guard let account = accounts.first else { throw AuthError.notAuthenticated }
        return try await getValidAccessToken(accountId: account.id)
    }

    public func buildAuthURL(clientId: String, redirectURI: String = AppConstants.googleRedirectURI) -> URL {
        var components = URLComponents(string: AppConstants.googleOAuthBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: AppConstants.googleScopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: AppConstants.googleOAuthPromptMode),
        ]
        return components.url!
    }

    public func exchangeAndSaveAccount(code: String, redirectURI: String = AppConstants.googleRedirectURI) async throws -> GoogleAccount {
        let creds = try loadCredentials()
        var request = URLRequest(url: URL(string: AppConstants.googleTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "client_id": creds.installed.clientId,
            "client_secret": creds.installed.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        request.httpBody = formEncoded(body).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed("HTTP error: \(body)")
        }
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        let userInfo = try await fetchUserInfo(accessToken: tokenResponse.accessToken)
        let db = DatabaseService.shared
        let accountId = userInfo.email
        if var existing = try await db.fetchAccount(id: accountId) {
            existing.email = userInfo.email
            existing.displayName = userInfo.name
            existing.accessToken = tokenResponse.accessToken
            existing.refreshToken = tokenResponse.refreshToken ?? existing.refreshToken
            existing.expirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
            existing.scope = tokenResponse.scope
            try await db.updateAccount(existing)
            return existing
        }
        let account = GoogleAccount(
            id: accountId,
            email: userInfo.email,
            displayName: userInfo.name,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60)),
            scope: tokenResponse.scope
        )
        return try await db.createAccount(account)
    }

    private func refreshAccessToken(refreshToken: String, clientId: String, clientSecret: String) async throws -> SavedToken {
        var request = URLRequest(url: URL(string: AppConstants.googleTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
        ]
        request.httpBody = formEncoded(body).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.refreshFailed("HTTP error: \(body)")
        }
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        return SavedToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60)),
            scope: tokenResponse.scope
        )
    }

    private func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.userInfoFailed("HTTP error: \(body)")
        }
        return try JSONDecoder().decode(GoogleUserInfo.self, from: data)
    }

    private nonisolated func formEncoded(_ values: [String: String]) -> String {
        values.map { key, value in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(escaped)"
        }
        .joined(separator: "&")
    }
}

public enum AuthError: LocalizedError {
    case noRefreshToken
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case notAuthenticated
    case userInfoFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noRefreshToken: "No refresh token available. Please re-authenticate."
        case .tokenExchangeFailed(let msg): "Token exchange failed: \(msg)"
        case .refreshFailed(let msg): "Token refresh failed: \(msg)"
        case .notAuthenticated: "Not authenticated. Please sign in with Google."
        case .userInfoFailed(let msg): "Google user info failed: \(msg)"
        }
    }
}
