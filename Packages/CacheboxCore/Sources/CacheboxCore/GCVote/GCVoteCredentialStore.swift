import Foundation
import Security

/// Where the GCVote password is kept. Cachebox keeps it in its settings file (`SettingEncryptedString
/// GcVotePassword`); here it goes into the keychain, like the Geocaching tokens.
public protocol GCVoteCredentialStoring: Sendable {
    func load() throws -> GCVoteCredentials?
    func save(_ credentials: GCVoteCredentials) throws
    func clear() throws
}

/// Keeps user name and password in the keychain (`kSecAttrAccessibleAfterFirstUnlock`, so that an import can also
/// run while the screen is locked).
public struct GCVoteKeychainStore: GCVoteCredentialStoring {
    public let service: String
    public let account: String

    public init(service: String = "de.team-cachebox.icachebox.gcvote", account: String = "credentials") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> GCVoteCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try? JSONDecoder().decode(Stored.self, from: data).credentials
        case errSecItemNotFound:
            return nil
        default:
            throw GeocachingKeychainError(status: status, operation: "lesen")
        }
    }

    public func save(_ credentials: GCVoteCredentials) throws {
        let data = try JSONEncoder().encode(Stored(credentials))
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

    /// `GCVoteCredentials` itself stays free of `Codable`, so that a password is never encoded by accident.
    private struct Stored: Codable {
        var username: String
        var password: String

        init(_ credentials: GCVoteCredentials) {
            username = credentials.username
            password = credentials.password
        }

        var credentials: GCVoteCredentials { GCVoteCredentials(username: username, password: password) }
    }
}

/// Store for tests and previews - keeps the credentials in memory only.
public final class GCVoteMemoryCredentialStore: GCVoteCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: GCVoteCredentials?

    public init(credentials: GCVoteCredentials? = nil) {
        self.credentials = credentials
    }

    public func load() throws -> GCVoteCredentials? { lock.withLock { credentials } }
    public func save(_ credentials: GCVoteCredentials) throws { lock.withLock { self.credentials = credentials } }
    public func clear() throws { lock.withLock { credentials = nil } }
}
