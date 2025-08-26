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
    
    lazy var client: SupabaseClient = {
        guard let path = Bundle.main.path(forResource: "Supabase-Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let url = plist["SUPABASE_URL"] as? String,
              let anonKey = plist["SUPABASE_ANON_KEY"] as? String else {
            fatalError("Supabase configuration not found. Please check Supabase-Config.plist")
        }
        
        return SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: anonKey
        )
    }()
    
    private init() {}
}
