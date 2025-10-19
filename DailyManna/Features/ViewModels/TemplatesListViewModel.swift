import Foundation
import Combine

@MainActor
final class TemplatesListViewModel: ObservableObject {
    @Published var templates: [Template] = []
    @Published var seriesByTemplateId: [UUID: Series] = [:]
    @Published var remainingByTemplateId: [UUID: Int] = [:]
    @Published var isPresentingEditor: Bool = false
    @Published var editingTemplate: Template?
    private var lastUserId: UUID?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: Notification.Name("dm.templates.changed"), object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { await self?.reload() }
        }
    }
    
    deinit {
        if let ob = observer { NotificationCenter.default.removeObserver(ob) }
    }

    func load(userId: UUID) async {
        do {
            let deps = Dependencies.shared
            let uc = try deps.resolve(type: TemplatesUseCases.self)
            // Ensure local repo is hydrated on cold-start (iOS fresh install)
            await uc.refreshFromRemoteIfNeeded(ownerId: userId)
            templates = try await uc.list(ownerId: userId)
            lastUserId = userId
            let serUC = try deps.resolve(type: SeriesUseCases.self)
            let allSeries = try await serUC.list(ownerId: userId)
            var map: [UUID: Series] = [:]
            for s in allSeries { map[s.templateId] = s }
            seriesByTemplateId = map
            await recomputeRemaining(userId: userId)
        } catch {
            Logger.shared.error("Failed to load templates", category: .ui, error: error)
        }
    }

    private func reload() async {
        guard let uid = lastUserId else { return }
        await load(userId: uid)
    }

    func presentNewTemplate() {
        isPresentingEditor = true
        editingTemplate = nil
    }

    func pauseResume(templateId: UUID, userId: UUID) async {
        do {
            let deps = Dependencies.shared
            let uc = try deps.resolve(type: SeriesUseCases.self)
            if var s = seriesByTemplateId[templateId] {
                s.status = (s.status == "active") ? "paused" : "active"
                try await uc.update(s)
            } else {
                // No series yet: create a default weekly series starting today with current weekday anchor
                let cal = Calendar.current
                let starts = cal.startOfDay(for: Date())
                let anchor = cal.component(.weekday, from: starts)
                let tz = TimeZone.current.identifier
                let newSeries = Series(templateId: templateId, ownerId: userId, startsOn: starts, endsOn: nil, timezoneIdentifier: tz, status: "active", lastGeneratedAt: nil, intervalWeeks: 1, anchorWeekday: anchor)
                try await uc.create(newSeries)
            }
            await load(userId: userId)
        } catch {
            Logger.shared.error("Failed to pause/resume or create series", category: .ui, error: error)
        }
    }

    func skipNext(templateId: UUID, userId: UUID) async {
        guard var s = seriesByTemplateId[templateId] else { return }
        let cal = Calendar.current
        let weeks = max(1, s.intervalWeeks)
        if let next = cal.date(byAdding: .day, value: 7 * weeks, to: s.startsOn) {
            s.startsOn = next
        }
        do {
            let deps = Dependencies.shared
            let uc = try deps.resolve(type: SeriesUseCases.self)
            try await uc.update(s)
            await load(userId: userId)
        } catch {
            Logger.shared.error("Failed to skip next occurrence", category: .ui, error: error)
        }
    }

    func recomputeRemaining(userId: UUID) async {
        var result: [UUID: Int] = [:]
        do {
            let deps = Dependencies.shared
            let repo = try deps.resolve(type: TasksRepository.self)
            let allTasks = try await repo.fetchTasks(for: userId, in: nil)
            for tpl in templates {
                guard let quota = tpl.endAfterCount, let series = seriesByTemplateId[tpl.id] else { continue }
                let generated = allTasks.filter { $0.seriesId == series.id && $0.deletedAt == nil }.count
                result[tpl.id] = max(0, quota - generated)
            }
        } catch {
            Logger.shared.error("Failed to compute remaining counts", category: .ui, error: error)
        }
        remainingByTemplateId = result
    }

    func nextRunDate(templateId: UUID) -> Date? {
        guard let s = seriesByTemplateId[templateId] else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Prefer rule-driven calculation when available
        if let rule = s.rule {
            let engine = RecurrenceEngine()
            var probe = max(cal.startOfDay(for: s.startsOn), today)
            var safety = 0
            // Advance until we find a next occurrence >= today
            while let next = engine.nextOccurrence(from: probe, rule: rule, calendar: cal), safety < 3650 {
                safety += 1
                if next >= today { return next }
                probe = next
            }
            return nil
        }
        // Legacy weekly fallback
        var d = cal.startOfDay(for: s.startsOn)
        let interval = max(1, s.intervalWeeks)
        if d < today {
            let comps = cal.dateComponents([.weekOfYear], from: d, to: today)
            let weeks = (comps.weekOfYear ?? 0)
            let steps = (weeks / interval) + (weeks % interval == 0 ? 0 : 1)
            d = cal.date(byAdding: .weekOfYear, value: steps * interval, to: d) ?? d
        }
        if let anchor = s.anchorWeekday {
            var aligned = d
            while cal.component(.weekday, from: aligned) != anchor {
                aligned = cal.date(byAdding: .day, value: 1, to: aligned) ?? aligned
            }
            d = aligned
        }
        return d
    }
}
