//
//  TimeBucket.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Represents the five fixed time horizons for organizing tasks
public enum TimeBucket: String, CaseIterable, Identifiable, Codable {
    case thisWeek = "THIS_WEEK"
    case weekend = "WEEKEND"
    case nextWeek = "NEXT_WEEK"
    case nextMonth = "NEXT_MONTH"
    case routines = "ROUTINES"
    
    public var id: String { self.rawValue }
    
    public var displayName: String {
        switch self {
        case .thisWeek: return "This Week"
        case .weekend: return "Weekend"
        case .nextWeek: return "Next Week"
        case .nextMonth: return "Next Month"
        case .routines: return "Routines"
        }
    }
    
    public var sortOrder: Int {
        switch self {
        case .thisWeek: return 0
        case .weekend: return 1
        case .nextWeek: return 2
        case .nextMonth: return 3
        case .routines: return 4
        }
    }
}
