import Foundation
@testable import DailyManna

enum TestFactories {
    static func userId(_ seed: Int = 1) -> UUID {
        // Deterministic UUID from a simple seeded RNG → hex string → UUID
        var generator = SeededRandomNumberGenerator(seed: UInt64(seed))
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        for _ in 0..<16 { bytes.append(UInt8.random(in: 0...255, using: &generator)) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        // Format 8-4-4-4-12
        let formatted = String(hex.prefix(8)) + "-" +
                        String(hex.dropFirst(8).prefix(4)) + "-" +
                        String(hex.dropFirst(12).prefix(4)) + "-" +
                        String(hex.dropFirst(16).prefix(4)) + "-" +
                        String(hex.dropFirst(20).prefix(12))
        return UUID(uuidString: formatted) ?? UUID()
    }
    
    static func task(
        id: UUID = UUID(),
        userId: UUID = userId(),
        bucket: TimeBucket = .thisWeek,
        title: String = "Sample Task",
        now: Date = ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!
    ) -> Task {
        Task(
            id: id,
            userId: userId,
            bucketKey: bucket,
            title: title,
            description: nil,
            dueAt: nil,
            recurrenceRule: nil,
            isCompleted: false,
            completedAt: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            version: 1,
            remoteId: nil,
            needsSync: true
        )
    }
    
    static func label(
        id: UUID = UUID(),
        userId: UUID = userId(),
        name: String = "@work",
        color: String = "#007AFF",
        now: Date = ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!
    ) -> Label {
        Label(
            id: id,
            userId: userId,
            name: name,
            color: color,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            version: 1,
            remoteId: nil,
            needsSync: true
        )
    }
}

// Simple deterministic RNG for UUID factory
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}


