import Foundation

public enum TaskPriority: String, Codable, CaseIterable, Equatable, Hashable {
    case low
    case normal
    case high
    case urgent
}
