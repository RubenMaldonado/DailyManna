//
//  TaskLabelEntity.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData model for TaskLabel junction entities
@Model
final class TaskLabelEntity {
    var taskId: UUID
    var labelId: UUID
    var userId: UUID // For RLS and consistency
    
    // Note: This is a junction entity for many-to-many relationships
    // Relationships are handled through repository queries using taskId and labelId foreign keys
    
    init(
        taskId: UUID,
        labelId: UUID,
        userId: UUID
    ) {
        self.taskId = taskId
        self.labelId = labelId
        self.userId = userId
    }
}
