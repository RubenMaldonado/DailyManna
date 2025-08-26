//
//  SignInView.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @StateObject private var authService: AuthenticationService
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingAppleRawNonce: String?
    
    init() {
        _authService = StateObject(wrappedValue: {
            do {
                return try Dependencies.shared.resolve(type: AuthenticationService.self)
            } catch {
                fatalError("Failed to resolve AuthenticationService: \(error)")
            }
        }())
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // App Logo and Title
            VStack(spacing: 16) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 60))
                    .foregroundColor(Colors.primary)
                
                Text("Daily Manna")
                    .font(Typography.largeTitle)
                    .foregroundColor(Colors.onBackground)
                
                Text("Structure Your Week, Focus Your Mind")
                    .font(Typography.body)
                    .foregroundColor(Colors.onSurface)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Authentication Buttons
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    // Generate nonce pair and attach hashed to the request
                    let pair = authService.prepareAppleNonce()
                    // Store raw nonce in a hidden state via associated object using the request's internal context
                    // Since we can't store on request, we pass via closure capture to handler below
                    self.pendingAppleRawNonce = pair.raw
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = pair.hashed
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(8)
                
                Button(action: handleGoogleSignIn) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Continue with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Colors.surface)
                    .foregroundColor(Colors.onSurface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Colors.outline, lineWidth: 1)
                    )
                }
                .disabled(isLoading)
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundColor(Colors.error)
                    .multilineTextAlignment(.center)
                    .padding(.top)
            }
            
            Spacer()
            
            // Privacy Notice
            Text("By signing in, you agree to our privacy policy and terms of service.")
                .font(Typography.caption)
                .foregroundColor(Colors.onSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(24)
        .background(Colors.background)
    }
    
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        _Concurrency.Task {
            isLoading = true
            errorMessage = nil
            
            do {
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let identityToken = credential.identityToken,
                          let idTokenString = String(data: identityToken, encoding: .utf8) else {
                        throw AuthError.invalidCredentials
                    }
                    let rawNonce = pendingAppleRawNonce
                    pendingAppleRawNonce = nil
                    try await authService.signInWithApple(idToken: idTokenString, rawNonce: rawNonce)
                case .failure(let error):
                    throw error
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
    }
    
    private func handleGoogleSignIn() {
        _Concurrency.Task {
            isLoading = true
            errorMessage = nil
            
            do {
                try await authService.signInWithGoogle()
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
    }
}

#Preview {
    SignInView()
}
