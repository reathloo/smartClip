import Foundation
import CryptoKit
import Security

enum CryptoStoreError: LocalizedError {
    case keychain(OSStatus)
    case missingData

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain error: \(status)"
        case .missingData: "Encrypted data is incomplete."
        }
    }
}

struct CryptoStore: Sendable {
    private let key: SymmetricKey

    init(key: SymmetricKey) { self.key = key }

    static func loadOrCreate() throws -> Self {
        let service = "dev.smartclip.SmartClip.history-key"
        let account = "local-history"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else { throw CryptoStoreError.missingData }
            return Self(key: SymmetricKey(data: data))
        }
        guard status == errSecItemNotFound else { throw CryptoStoreError.keychain(status) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var add = query
        add.removeValue(forKey: kSecReturnData as String)
        add.removeValue(forKey: kSecMatchLimit as String)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CryptoStoreError.keychain(addStatus) }
        return Self(key: key)
    }

    func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw CryptoStoreError.missingData }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }

    func digest(_ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }
}
