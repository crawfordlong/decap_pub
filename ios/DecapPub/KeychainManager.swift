import Foundation
import Security

/// Secure storage manager for sensitive credentials using iOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.decappub.github"
    
    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case invalidData
        case unhandledError(status: OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in Keychain"
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .invalidData:
                return "Invalid data format"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Save
    
    /// Save a string value to the Keychain
    func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Delete any existing item first
        try? delete(for: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Retrieve
    
    /// Retrieve a string value from the Keychain
    func retrieve(for key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return string
    }
    
    /// Retrieve a string value from the Keychain, returning nil if not found
    func retrieveOptional(for key: String) -> String? {
        return try? retrieve(for: key)
    }
    
    // MARK: - Delete
    
    /// Delete a value from the Keychain
    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Update
    
    /// Update an existing value in the Keychain
    func update(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            // Item doesn't exist, create it
            try save(value, for: key)
        } else if status != errSecSuccess {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Convenience for GitHub Token
    
    private let githubTokenKey = "githubToken"
    
    var githubToken: String {
        get {
            retrieveOptional(for: githubTokenKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                try? delete(for: githubTokenKey)
            } else {
                try? update(newValue, for: githubTokenKey)
            }
        }
    }
}
