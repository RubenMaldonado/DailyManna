//
//  SupabaseConfig.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Supabase

final class SupabaseConfig {
    static let shared = SupabaseConfig()
    
    // Redirect URL used by ASWebAuthenticationSession to return to the app.
    // We default to a custom scheme based on the app bundle identifier.
    // Make sure this scheme is registered under URL Types in the app target settings.
    lazy var redirectToURL: URL = {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.rubentena.DailyManna"
        // Callback path can be any constant string; it must match the value you add in Supabase Auth > URL Configuration > Additional Redirect URLs
        return URL(string: "\(bundleId)://auth-callback")!
    }()
    
    lazy var client: SupabaseClient = {
        guard let path = Bundle.main.path(forResource: "Supabase-Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let url = plist["SUPABASE_URL"] as? String,
              let anonKey = plist["SUPABASE_ANON_KEY"] as? String else {
            fatalError("Supabase configuration not found. Please check Supabase-Config.plist")
        }
        
        return SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: anonKey,
            options: .init(
                auth: .init(
                    // Provide a global redirect URL so OAuth calls work without passing redirectTo each time
                    redirectToURL: redirectToURL
                )
            )
        )
    }()
    
    private init() {}
}
