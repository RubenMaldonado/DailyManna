//
//  AuthenticationService.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Supabase
import AuthenticationServices
import SwiftUI
import CryptoKit

@MainActor
final class AuthenticationService: ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authState: AuthState = .unauthenticated
    
    // MARK: - Private Properties
    private let client: SupabaseClient
    
    enum AuthState {
        case unauthenticated
        case authenticating
        case authenticated(User)
        case error(Error)
    }
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    // MARK: - Auth State Management
    /// Call this once (e.g., from a SwiftUI .task) to restore any session and start listening for auth changes.
    func runAuthLifecycle() async {
        await restoreSession()
        await listenForAuthChanges()
    }
    
    /// Long-running listener for Supabase auth changes. Safe to await forever inside .task.
    private func listenForAuthChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            await handleAuthStateChange(event: event, session: session)
        }
    }
    
    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        Logger.shared.info("Auth state changed: \(event)", category: .auth)
        
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated:
            if let session { await setAuthenticatedState(with: session) }
        case .signedOut:
            await setUnauthenticatedState()
        case .passwordRecovery:
            Logger.shared.info("Password recovery initiated", category: .auth)
        case .mfaChallengeVerified:
            Logger.shared.info("MFA challenge verified", category: .auth)
        default:
            // Future-proof against new cases in the SDK
            Logger.shared.info("Unhandled auth event: \(event)", category: .auth)
        }
    }
    
    private func setAuthenticatedState(with session: Session) async {
        do {
            let userResponse = try await client.auth.user()
            
            let fullName = extractFullName(from: userResponse.userMetadata)
            
            let domainUser = User(
                id: userResponse.id,
                email: userResponse.email ?? "",
                fullName: fullName,
                createdAt: userResponse.createdAt,
                updatedAt: userResponse.updatedAt
            )
            
            currentUser = domainUser
            isAuthenticated = true
            authState = .authenticated(domainUser)
            
            // Store session securely
            try await KeychainService.shared.storeSession(session)
            Logger.shared.info("User authenticated successfully: \(domainUser.email)", category: .auth)
            
        } catch {
            Logger.shared.error("Failed to set authenticated state", category: .auth, error: error)
            authState = .error(error)
            await setUnauthenticatedState()
        }
    }
    
    private func extractFullName(from metadata: [String: Any]?) -> String {
        guard let metadata = metadata else { return "" }
        if let fullName = metadata["full_name"] as? String { return fullName }
        if let userInfo = metadata["user"] as? [String: Any], let fullName = userInfo["full_name"] as? String { return fullName }
        return ""
    }
    
    private func setUnauthenticatedState() async {
        currentUser = nil
        isAuthenticated = false
        authState = .unauthenticated
        try? await KeychainService.shared.clearSession()
    }
    
    // MARK: - Sign In Methods
    /// Prepare a nonce pair for SIWA: (raw, hashed-for-request)
    func prepareAppleNonce() -> (raw: String, hashed: String) {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let hashed = sha256(raw)
        return (raw, hashed)
    }

    /// Exchange Apple id_token with Supabase. Provide the SAME raw nonce used to build request.nonce.
    func signInWithApple(idToken: String, rawNonce: String?) async throws {
        authState = .authenticating
        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    accessToken: nil,
                    nonce: rawNonce
                )
            )
            Logger.shared.info("Apple Sign-In initiated successfully", category: .auth)
        } catch {
            Logger.shared.error("Apple Sign-In failed", category: .auth, error: error)
            authState = .unauthenticated
            throw error
        }
    }
    
    func signInWithGoogle() async throws {
        authState = .authenticating
        do {
            _ = try await client.auth.signInWithOAuth(provider: .google)
            Logger.shared.info("Google OAuth initiated successfully", category: .auth)
        } catch {
            Logger.shared.error("Google OAuth failed", category: .auth, error: error)
            authState = .unauthenticated
            throw error
        }
    }
    
    func signOut() async throws {
        authState = .authenticating
        try await client.auth.signOut()
        Logger.shared.info("Sign out initiated successfully", category: .auth)
        await setUnauthenticatedState()
    }
    
    // MARK: - Session Management
    func restoreSession() async {
        do {
            if let session = try await KeychainService.shared.getSession() {
                try await client.auth.setSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
                Logger.shared.info("Session restored successfully", category: .auth)
                await setAuthenticatedState(with: session)
            } else {
                Logger.shared.info("No stored session found", category: .auth)
                await setUnauthenticatedState()
            }
        } catch {
            Logger.shared.error("Failed to restore session", category: .auth, error: error)
            await setUnauthenticatedState()
        }
    }
}

// MARK: - Apple Sign In Delegate
// Keep delegate only for presentation context if needed in future flows
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { fatalError("No window available") }
        return window
        #else
        return NSApplication.shared.windows.first ?? NSWindow()
        #endif
    }
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError
    case unknownError
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid credentials provided"
        case .networkError: return "Network error occurred"
        case .unknownError: return "An unknown error occurred"
        }
    }
}

// MARK: - Helpers
private func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
