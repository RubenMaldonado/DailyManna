//
//  TimeBucketEntity.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData model for fixed time buckets
@Model
final class TimeBucketEntity {
    @Attribute(.unique) var key: String
    var name: String
    
    init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}


