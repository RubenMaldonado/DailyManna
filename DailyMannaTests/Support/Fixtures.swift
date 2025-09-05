import Foundation
@testable import DailyManna

enum TestFixtures {
    /// Generate N labels deterministically
    static func makeLabels(count: Int, userId: UUID, seed: Int = 42) -> [Label] {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        var labels: [Label] = []
        labels.reserveCapacity(count)
        for i in 0..<count {
            let id = UUID()
            let hue: Double = Double.random(in: 0...1, using: &rng)
            let color = hslToHex(h: hue, s: 0.7, l: 0.5)
            let name = "Label_\(i)"
            labels.append(TestFactories.label(id: id, userId: userId, name: name, color: color))
        }
        return labels
    }

    /// Generate N tasks deterministically across the provided buckets
    static func makeTasks(
        count: Int,
        userId: UUID,
        seed: Int = 7,
        buckets: [TimeBucket] = TimeBucket.allCases,
        dueRate: Double = 0.6,
        completeRate: Double = 0.2
    ) -> [Task] {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        var tasks: [Task] = []
        tasks.reserveCapacity(count)
        let now = Date()
        for i in 0..<count {
            let bucket = buckets[Int.random(in: 0..<buckets.count, using: &rng)]
            var t = TestFactories.task(
                id: UUID(),
                userId: userId,
                bucket: bucket,
                title: "Task #\(i)",
                now: now
            )
            // Random due
            if Double.random(in: 0...1, using: &rng) < dueRate {
                let offsetDays = Int.random(in: -7...14, using: &rng)
                if let due = Calendar.current.date(byAdding: .day, value: offsetDays, to: now) {
                    t.dueAt = due
                }
            }
            // Random completion
            if Double.random(in: 0...1, using: &rng) < completeRate {
                t.isCompleted = true
                t.completedAt = now
            }
            // Spread positions
            t.position = Double(i) * 1024.0
            tasks.append(t)
        }
        return tasks
    }

    /// Build saved filters deterministically from a label pool
    static func makeSavedFilters(
        count: Int,
        userId: UUID,
        fromLabels labels: [Label],
        seed: Int = 99
    ) -> [SavedFilter] {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        var filters: [SavedFilter] = []
        filters.reserveCapacity(count)
        for i in 0..<count {
            let k = Int.random(in: 1...min(5, max(1, labels.count)), using: &rng)
            let chosen = labels.shuffled(using: &rng).prefix(k).map { $0.id }
            let now = Date()
            let f = SavedFilter(
                id: UUID(),
                userId: userId,
                name: "Filter_\(i)",
                labelIds: chosen,
                matchAll: Bool.random(using: &rng),
                createdAt: now,
                updatedAt: now
            )
            filters.append(f)
        }
        return filters
    }

    /// Create pairs (Task, [Label]) by assigning random labels per task using provided pool
    static func assignLabelsToTasks(
        tasks: [Task],
        labelPool: [Label],
        minPerTask: Int = 0,
        maxPerTask: Int = 3,
        seed: Int = 1337
    ) -> [(Task, [Label])] {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        return tasks.map { task in
            let n = Int.random(in: minPerTask...max(maxPerTask, minPerTask), using: &rng)
            let chosen = n > 0 ? Array(labelPool.shuffled(using: &rng).prefix(n)) : []
            return (task, chosen)
        }
    }
}

// MARK: - Utilities
private func hslToHex(h: Double, s: Double, l: Double) -> String {
    // Convert HSL to RGB, then to hex; simple implementation adequate for test data
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs(fmod(h * 6, 2) - 1))
    let m = l - c/2
    let (r1, g1, b1): (Double, Double, Double)
    switch h * 6 {
    case 0..<1: (r1, g1, b1) = (c, x, 0)
    case 1..<2: (r1, g1, b1) = (x, c, 0)
    case 2..<3: (r1, g1, b1) = (0, c, x)
    case 3..<4: (r1, g1, b1) = (0, x, c)
    case 4..<5: (r1, g1, b1) = (x, 0, c)
    default:    (r1, g1, b1) = (c, 0, x)
    }
    let r = Int(((r1 + m) * 255.0).rounded())
    let g = Int(((g1 + m) * 255.0).rounded())
    let b = Int(((b1 + m) * 255.0).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}
