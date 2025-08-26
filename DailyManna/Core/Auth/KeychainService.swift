//
//  KeychainService.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Security
import Supabase

final class KeychainService {
    static let shared = KeychainService()
    private let service = "com.dailymanna.session"
    private let account = "supabase_session"
    
    private init() {}
    
    func storeSession(_ session: Session) async throws {
        let data = try JSONEncoder().encode(session)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            Logger.shared.error("Failed to store session in keychain", category: .auth, error: nil)
            throw KeychainError.storeFailed
        }
        
        Logger.shared.info("Session stored successfully in keychain", category: .auth)
    }
    
    func getSession() async throws -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            
            let session = try JSONDecoder().decode(Session.self, from: data)
            Logger.shared.info("Session retrieved successfully from keychain", category: .auth)
            return session
            
        case errSecItemNotFound:
            Logger.shared.info("No session found in keychain", category: .auth)
            return nil
            
        default:
            Logger.shared.error("Failed to retrieve session from keychain", category: .auth, error: nil)
            throw KeychainError.retrieveFailed
        }
    }
    
    func clearSession() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.shared.error("Failed to clear session from keychain", category: .auth, error: nil)
            throw KeychainError.deleteFailed
        }
        
        Logger.shared.info("Session cleared from keychain", category: .auth)
    }
}

enum KeychainError: LocalizedError {
    case storeFailed
    case retrieveFailed
    case deleteFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .storeFailed:
            return "Failed to store data in keychain"
        case .retrieveFailed:
            return "Failed to retrieve data from keychain"
        case .deleteFailed:
            return "Failed to delete data from keychain"
        case .invalidData:
            return "Invalid data format in keychain"
        }
    }
}
