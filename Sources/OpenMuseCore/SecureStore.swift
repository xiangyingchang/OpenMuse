import Foundation
import Security

public enum SecureStoreError: Error, LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let status): "系统钥匙串操作失败（\(status)）。"
        }
    }
}

public enum SecureStore {
    private static let service = "org.openmuse.credentials"
    private static let bridgeService = "org.openmuse.device-bridge"
    private static let integrationService = "org.openmuse.integrations"

    #if DEBUG
    /// An opt-in test backend keeps the broad Core suite independent from a
    /// user's login Keychain. The default remains the system Keychain, and the
    /// dedicated credential-store test can still exercise that integration.
    private static let inMemoryTestBackend = InMemoryKeychainBackend()
    private static var usesInMemoryTestBackend: Bool {
        ProcessInfo.processInfo.environment["OPENMUSE_TEST_IN_MEMORY_KEYCHAIN"] == "1"
    }

    private final class InMemoryKeychainBackend: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func read(service: String, account: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[Self.key(service: service, account: account)]
        }

        func save(_ value: String, service: String, account: String) {
            lock.lock()
            defer { lock.unlock() }
            values[Self.key(service: service, account: account)] = value
        }

        func delete(service: String, account: String) {
            lock.lock()
            defer { lock.unlock() }
            values.removeValue(forKey: Self.key(service: service, account: account))
        }

        private static func key(service: String, account: String) -> String {
            "\(service)\u{0}\(account)"
        }
    }
    #endif

    public static func readAPIKey(for configuration: ModelConfiguration) -> String? {
        read(service: service, account: configuration.credentialAccount)
    }

    /// Keychain reads can block while macOS unlocks or decrypts an item. Use this
    /// from UI-facing model code so a slow Keychain operation cannot stall the
    /// main actor (or the Mac bridge's HTTP handlers).
    public static func readAPIKeyAsync(for configuration: ModelConfiguration) async -> String? {
        await Task.detached(priority: .userInitiated) {
            readAPIKey(for: configuration)
        }.value
    }

    public static func saveAPIKey(_ value: String, for configuration: ModelConfiguration) throws {
        try save(value, service: service, account: configuration.credentialAccount)
    }

    public static func deleteAPIKey(for configuration: ModelConfiguration) throws {
        try delete(service: service, account: configuration.credentialAccount)
    }

    public static func readPairedMacToken() -> String? {
        read(service: bridgeService, account: "paired-mac")
    }

    public static func readPairedMacTokenAsync() async -> String? {
        await Task.detached(priority: .userInitiated) {
            readPairedMacToken()
        }.value
    }

    public static func savePairedMacToken(_ value: String) throws {
        try save(value, service: bridgeService, account: "paired-mac")
    }

    public static func deletePairedMacToken() throws {
        try delete(service: bridgeService, account: "paired-mac")
    }

    public static func readIntegrationToken(provider: String) -> String? {
        guard ["notion", "qq-mail", "gmail"].contains(provider) else { return nil }
        return read(service: integrationService, account: provider)
    }

    public static func saveIntegrationToken(_ value: String, provider: String) throws {
        guard ["notion", "qq-mail", "gmail"].contains(provider), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStoreError.status(errSecParam)
        }
        try save(value, service: integrationService, account: provider)
    }

    public static func deleteIntegrationToken(provider: String) throws {
        guard ["notion", "qq-mail", "gmail"].contains(provider) else { throw SecureStoreError.status(errSecParam) }
        try delete(service: integrationService, account: provider)
    }

    #if os(macOS)
    static func readBridgeDeviceToken(id: String, scope: String = "default") -> String? {
        read(service: bridgeService, account: "device:\(scope):\(id)")
    }

    static func saveBridgeDeviceToken(_ value: String, id: String, scope: String = "default") throws {
        try save(value, service: bridgeService, account: "device:\(scope):\(id)")
    }

    static func deleteBridgeDeviceToken(id: String, scope: String = "default") throws {
        try delete(service: bridgeService, account: "device:\(scope):\(id)")
    }
    #endif

    private static func read(service: String, account: String) -> String? {
        #if DEBUG
        if usesInMemoryTestBackend {
            return inMemoryTestBackend.read(service: service, account: account)
        }
        #endif

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    private static func save(_ value: String, service: String, account: String) throws {
        #if DEBUG
        if usesInMemoryTestBackend {
            inMemoryTestBackend.save(value, service: service, account: account)
            return
        }
        #endif

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard let data = value.data(using: .utf8) else { throw SecureStoreError.status(errSecParam) }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw SecureStoreError.status(status) }
        } else if update != errSecSuccess {
            throw SecureStoreError.status(update)
        }
    }

    private static func delete(service: String, account: String) throws {
        #if DEBUG
        if usesInMemoryTestBackend {
            inMemoryTestBackend.delete(service: service, account: account)
            return
        }
        #endif

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStoreError.status(status) }
    }
}
