import Foundation

/// Storage for the device bearer token. Production uses the Keychain.
public protocol TokenStore: Sendable {
    func readToken() -> String?
    func saveToken(_ token: String) throws
    func deleteToken()
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func readToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func saveToken(_ token: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }

    public func deleteToken() {
        lock.lock(); defer { lock.unlock() }
        token = nil
    }
}

/// Uses `primary` (the Keychain) and falls back to memory for this launch when it can't
/// save, e.g. an unsigned simulator build without Keychain entitlements. The app keeps
/// working; the device simply re-registers on next launch.
public final class FallbackTokenStore: TokenStore, @unchecked Sendable {
    private let primary: TokenStore
    private let memory = InMemoryTokenStore()
    private let lock = NSLock()
    private var usingMemory = false

    public init(primary: TokenStore) {
        self.primary = primary
    }

    private var isUsingMemory: Bool {
        lock.lock(); defer { lock.unlock() }
        return usingMemory
    }

    public func readToken() -> String? {
        isUsingMemory ? memory.readToken() : primary.readToken()
    }

    public func saveToken(_ token: String) throws {
        do {
            try primary.saveToken(token)
        } catch {
            lock.lock(); usingMemory = true; lock.unlock()
            try memory.saveToken(token)
        }
    }

    public func deleteToken() {
        primary.deleteToken()
        memory.deleteToken()
    }
}

#if canImport(Security)
import Security

public enum KeychainError: Error, Equatable, LocalizedError {
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "Halo couldn't use the Keychain (status \(status))."
        }
    }
}

/// Generic-password Keychain item, accessible after first unlock, never synced to iCloud.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "app.halo.api", account: String = "device-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
#endif
