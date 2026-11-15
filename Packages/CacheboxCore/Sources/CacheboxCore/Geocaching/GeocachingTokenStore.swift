import Foundation
import Security

/// What geocaching.com hands back: the token for the API calls plus the one that fetches a new one.
///
/// Cachebox keeps the same three values (`Settings.AccessToken`, `refreshToken`, `tokenExpiration`), only
/// encrypted in its settings file; here they go into the keychain.
public struct GeocachingTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    /// Missing only if the server left it out; the documentation says it expires after one year.
    public var refreshToken: String?
    /// `bearer` in the documentation's example; used verbatim in the `Authorization` header.
    public var tokenType: String
    /// `expires_in` turned into a point in time at the moment of the answer.
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, tokenType: String = "bearer", expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
    }

    /// Still usable in `leeway` seconds? A minute of slack keeps a request from dying halfway through.
    public func isValid(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        date.addingTimeInterval(leeway) < expiresAt
    }

    /// The value for the `Authorization` header.
    public var authorizationHeader: String {
        "\(tokenType.isEmpty ? "bearer" : tokenType) \(accessToken)"
    }
}

/// Where the tokens are kept between launches.
public protocol GeocachingTokenStoring: Sendable {
    func load() throws -> GeocachingTokens?
    func save(_ tokens: GeocachingTokens) throws
    func clear() throws
}

/// Keeps the tokens in the keychain - they are as good as a password and have no business in `UserDefaults`.
///
/// `kSecAttrAccessibleAfterFirstUnlock` so that the approach notification and other background work can still
/// refresh a token while the screen is locked.
public struct GeocachingKeychainStore: GeocachingTokenStoring {
    public let service: String
    public let account: String

    public init(service: String = "de.team-cachebox.icachebox.geocaching", account: String = "tokens") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> GeocachingTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            // A token from an older build that no longer decodes is treated as "not signed in".
            return try? JSONDecoder().decode(GeocachingTokens.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw GeocachingKeychainError(status: status, operation: "lesen")
        }
    }

    public func save(_ tokens: GeocachingTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw GeocachingKeychainError(status: addStatus, operation: "anlegen")
            }
        } else if status != errSecSuccess {
            throw GeocachingKeychainError(status: status, operation: "schreiben")
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeocachingKeychainError(status: status, operation: "löschen")
        }
    }
}

public struct GeocachingKeychainError: Error, LocalizedError, Equatable {
    public let status: OSStatus
    public let operation: String

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Fehler \(status)"
        return "Schlüsselbund (\(operation)): \(message)"
    }
}

/// Store for tests and previews - keeps the tokens in memory only.
public final class GeocachingMemoryTokenStore: GeocachingTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: GeocachingTokens?
    /// Set to let `save` fail, to test the path where the keychain says no.
    public var saveError: (any Error)?

    public init(tokens: GeocachingTokens? = nil) {
        self.tokens = tokens
    }

    public func load() throws -> GeocachingTokens? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: GeocachingTokens) throws {
        if let saveError { throw saveError }
        lock.withLock { self.tokens = tokens }
    }

    public func clear() throws {
        lock.withLock { tokens = nil }
    }
}
