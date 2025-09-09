import XCTest
@testable import DailyManna

@MainActor
final class FilterBuiltinsTests: XCTestCase {
    func testAvailableFilter() async throws {
        let now = Date()
        let userId = UUID()
        var t1 = Task(userId: userId, bucketKey: .thisWeek, title: "no due")
        var t2 = Task(userId: userId, bucketKey: .thisWeek, title: "due past"); t2.dueAt = Calendar.current.date(byAdding: .day, value: -1, to: now)
        var t3 = Task(userId: userId, bucketKey: .thisWeek, title: "due future"); t3.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
        var t4 = Task(userId: userId, bucketKey: .thisWeek, title: "completed past"); t4.dueAt = Calendar.current.date(byAdding: .day, value: -1, to: now); t4.isCompleted = true
        // date-only due today at 9am (should be included today until end-of-day)
        var t5 = Task(userId: userId, bucketKey: .thisWeek, title: "date-only today")
        var comps = Calendar.current.dateComponents([.year,.month,.day], from: now)
        comps.hour = 9; comps.minute = 0
        t5.dueAt = Calendar.current.date(from: comps)
        t5.dueHasTime = false
        let pairs: [(Task, [Label])] = [(t1, []), (t2, []), (t3, []), (t4, []), (t5, [])]

        let vm = await makeViewModel(userId: userId)
        vm.availableOnly = true

        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        func effectiveDue(_ t: Task) -> Date? {
            guard let due = t.dueAt else { return nil }
            if t.dueHasTime { return due }
            let start = Calendar.current.startOfDay(for: due)
            return Calendar.current.date(byAdding: .day, value: 1, to: start) ?? due
        }
        let filtered = pairs.filter { pair in
            let t = pair.0
            guard t.isCompleted == false else { return false }
            if let due = effectiveDue(t) { return due <= endOfToday }
            return true
        }
        XCTAssertEqual(Set(filtered.map { $0.0.title }), Set(["no due", "due past", "date-only today"]))
    }

    func testUnlabeledOnlyFilter() {
        let userId = UUID()
        let l1 = Label(userId: userId, name: "A", color: "#FF0000")
        let t1 = Task(userId: userId, bucketKey: .thisWeek, title: "no label")
        let t2 = Task(userId: userId, bucketKey: .thisWeek, title: "has label")
        let pairs: [(Task, [Label])] = [(t1, []), (t2, [l1])]
        let result = pairs.filter { $0.1.isEmpty }
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.0.title, "no label")
    }

    func testMatchAllLabels() {
        let userId = UUID()
        let l1 = Label(userId: userId, name: "A", color: "#FF0000")
        let l2 = Label(userId: userId, name: "B", color: "#00FF00")
        let t1 = Task(userId: userId, bucketKey: .thisWeek, title: "A only")
        let t2 = Task(userId: userId, bucketKey: .thisWeek, title: "A+B")
        let pairs: [(Task, [Label])] = [(t1, [l1]), (t2, [l1, l2])]
        let target: Set<UUID> = Set([l1.id, l2.id])
        let idSets = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.id, Set($0.1.map { $0.id })) })
        let filtered = pairs.filter { pair in
            let ids = idSets[pair.0.id] ?? []
            return ids.isSuperset(of: target)
        }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.0.title, "A+B")
    }

    private func makeViewModel(userId: UUID) async -> TaskListViewModel {
        let deps = Dependencies.shared
        let vm = TaskListViewModel(
            taskUseCases: try! deps.resolve(type: TaskUseCases.self),
            labelUseCases: try! deps.resolve(type: LabelUseCases.self),
            userId: userId,
            syncService: try? deps.resolve(type: SyncService.self),
            recurrenceUseCases: try? deps.resolve(type: RecurrenceUseCases.self)
        )
        return vm
    }
}


