//
//  DataMigration.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// Runs idempotent, lightweight data migrations at startup
enum DataMigration {
    static func runMigrations(modelContext: ModelContext) {
        // Placeholder: no-op migration. SyncStateEntity is added to schema; SwiftData handles lightweight migrations.
    }
}


