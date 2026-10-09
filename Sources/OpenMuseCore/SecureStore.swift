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

    public static func readAPIKey(for configuration: ModelConfiguration) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configuration.credentialAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    public static func saveAPIKey(_ value: String, for configuration: ModelConfiguration) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configuration.credentialAccount
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

    public static func deleteAPIKey(for configuration: ModelConfiguration) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configuration.credentialAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStoreError.status(status) }
    }

    public static func readPairedMacToken() -> String? {
        read(service: bridgeService, account: "paired-mac")
    }

    public static func savePairedMacToken(_ value: String) throws {
        try save(value, service: bridgeService, account: "paired-mac")
    }

    public static func deletePairedMacToken() throws {
        try delete(service: bridgeService, account: "paired-mac")
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStoreError.status(status) }
    }
}
