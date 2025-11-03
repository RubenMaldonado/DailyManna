import Foundation
import SwiftUI

@MainActor
final class NewTemplateViewModel: ObservableObject {
    // MARK: - Basics
    let userId: UUID
    private let editingTemplate: Template?
    private let existingSeries: Series?
    
    @Published var name: String = ""
    @Published var descriptionText: String = ""
    @Published var priority: TaskPriority = .normal
    @Published var defaultTime: Date = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @Published var selectedLabelIds: Set<UUID> = []
    
    // End rules
    enum EndRule: Equatable { case never, onDate(Date), afterCount(Int) }
    @Published var endRule: EndRule = .never
    
    // MARK: - Recurrence state
    enum Frequency: String, CaseIterable { case daily, weekly, monthly, yearly }
    @Published var frequency: Frequency = .weekly
    @Published var interval: Int = 1
    
    // Weekly
    @Published var selectedWeekdays: Set<Int> = [] // 1=Sun ... 7=Sat (Calendar.current)
    
    // Monthly
    enum MonthlyKind: String, CaseIterable { case dayOfMonth, nthWeekday }
    @Published var monthlyKind: MonthlyKind = .dayOfMonth
    @Published var monthDay: Int = 1 // 1..31
    @Published var monthlyOrdinal: Int = 1 // 1,2,3,4,-1
    @Published var monthlyWeekday: Int = 2 // Monday default
    
    // Yearly
    @Published var yearlyMonth: Int = Calendar.current.component(.month, from: Date())
    @Published var yearlyKind: MonthlyKind = .dayOfMonth
    @Published var yearlyDay: Int = 1
    @Published var yearlyOrdinal: Int = 1
    @Published var yearlyWeekday: Int = 2
    
    // Range
    @Published var startsOn: Date = Calendar.current.startOfDay(for: Date())
    @Published var timezoneIdentifier: String = TimeZone.current.identifier
    
    // Derived
    @Published private(set) var summaryText: String = ""
    @Published private(set) var upcomingPreview: [Date] = []
    
    private let recurrenceEngine = RecurrenceEngine()
    
    init(userId: UUID, editing: Template? = nil, series: Series? = nil) {
        self.userId = userId
        self.editingTemplate = editing
        self.existingSeries = series
        // Prefill from editing template if provided
        if let tpl = editing {
            name = tpl.name
            descriptionText = tpl.description ?? ""
            priority = tpl.priority
            selectedLabelIds = Set(tpl.labelsDefault)
            if let comps = tpl.defaultDueTime, let h = comps.hour, let m = comps.minute,
               let d = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) {
                defaultTime = d
            }
            if let count = tpl.endAfterCount { endRule = .afterCount(count) }
        }
        if let ser = series {
            startsOn = ser.startsOn
            if let end = ser.endsOn { endRule = .onDate(end) }
            if let rule = ser.rule {
                // Prefill from rule (preferred)
                switch rule.freq {
                case .daily:
                    frequency = .daily
                    interval = rule.interval
                case .weekly:
                    frequency = .weekly
                    interval = rule.interval
                    let codes = Set(rule.byWeekday ?? [])
                    selectedWeekdays = Set(codes.compactMap { code in
                        switch code { case "SU": return 1; case "MO": return 2; case "TU": return 3; case "WE": return 4; case "TH": return 5; case "FR": return 6; case "SA": return 7; default: return nil }
                    })
                case .monthly:
                    frequency = .monthly
                    interval = rule.interval
                    if let day = rule.byMonthDay?.first {
                        monthlyKind = .dayOfMonth
                        monthDay = day
                    } else if let pos = rule.bySetPos?.first, let wd = rule.byWeekday?.first {
                        monthlyKind = .nthWeekday
                        monthlyOrdinal = pos
                        monthlyWeekday = { switch wd { case "SU": return 1; case "MO": return 2; case "TU": return 3; case "WE": return 4; case "TH": return 5; case "FR": return 6; case "SA": return 7; default: return 2 } }()
                    }
                case .yearly:
                    frequency = .yearly
                    interval = rule.interval
                    if let m = rule.byMonth?.first { yearlyMonth = m }
                    if let day = rule.byMonthDay?.first {
                        yearlyKind = .dayOfMonth
                        yearlyDay = day
                    } else if let pos = rule.bySetPos?.first, let wd = rule.byWeekday?.first {
                        yearlyKind = .nthWeekday
                        yearlyOrdinal = pos
                        yearlyWeekday = { switch wd { case "SU": return 1; case "MO": return 2; case "TU": return 3; case "WE": return 4; case "TH": return 5; case "FR": return 6; case "SA": return 7; default: return 2 } }()
                    }
                }
                // Time from rule if no template default time
                if let t = rule.time, let d = timeFromString(t) { defaultTime = d }
            } else {
                // Legacy weekly fallback
                frequency = .weekly
                interval = max(1, ser.intervalWeeks)
                if let wd = ser.anchorWeekday { selectedWeekdays = [wd] }
            }
        }
        recomputePreview()
    }
    
    // MARK: - Intents
    func setEndAfterCount(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed), n > 0 { endRule = .afterCount(min(n, 999)) }
    }
    
    func setEndOnDate(_ date: Date) { endRule = .onDate(Calendar.current.startOfDay(for: date)) }
    func setEndNever() { endRule = .never }
    
    func recomputePreview() {
        summaryText = buildSummary()
        upcomingPreview = nextOccurrences(count: 10)
    }
    
    var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && validateRecurrence() == nil
    }
    
    // MARK: - Save
    func save() async {
        guard canSave else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: defaultTime)
        do {
            let deps = Dependencies.shared
            let tplUC = try deps.resolve(type: TemplatesUseCases.self)
            if var editing = editingTemplate {
                editing.name = name
                editing.description = descriptionText.isEmpty ? nil : descriptionText
                editing.defaultDueTime = comps
                editing.priority = priority
                editing.labelsDefault = Array(selectedLabelIds)
                switch endRule {
                case .afterCount(let n): editing.endAfterCount = n
                default: editing.endAfterCount = nil
                }
                editing.updatedAt = Date()
                try await tplUC.update(editing)
                // Update existing series with rule-driven scheduling, or create one if missing
                if var ser = existingSeries {
                    ser.startsOn = Calendar.current.startOfDay(for: startsOn)
                    ser.endsOn = {
                        if case .onDate(let d) = endRule { return Calendar.current.startOfDay(for: d) }
                        return nil
                    }()
                    // Build rule from UI selections
                    let rule = buildRule()
                    ser.rule = rule
                    // Maintain legacy weekly fields for compatibility when weekly
                    if frequency == .weekly {
                        ser.intervalWeeks = interval
                        ser.anchorWeekday = selectedWeekdays.sorted().first
                    }
                    ser.updatedAt = Date()
                    let serUC = try deps.resolve(type: SeriesUseCases.self)
                    try await serUC.update(ser)
                } else {
                    // No existing series: create one using current rule and dates
                    let cal = Calendar.current
                    let starts = cal.startOfDay(for: startsOn)
                    let ends: Date? = {
                        if case .onDate(let d) = endRule { return cal.startOfDay(for: d) }
                        return nil
                    }()
                    let newSeries = Series(
                        templateId: editing.id,
                        ownerId: userId,
                        startsOn: starts,
                        endsOn: ends,
                        timezoneIdentifier: timezoneIdentifier,
                        status: "active",
                        lastGeneratedAt: nil,
                        intervalWeeks: interval,
                        anchorWeekday: selectedWeekdays.sorted().first,
                        rule: buildRule()
                    )
                    let serUC = try deps.resolve(type: SeriesUseCases.self)
                    try await serUC.create(newSeries)
                }
                NotificationCenter.default.post(name: Notification.Name("dm.templates.changed"), object: nil)
            } else {
                var template = Template(ownerId: userId, name: name, description: descriptionText.isEmpty ? nil : descriptionText, labelsDefault: Array(selectedLabelIds), defaultBucket: .routines, defaultDueTime: comps, priority: priority, status: "active")
                template.updatedAt = Date()
                try await tplUC.create(template)
                NotificationCenter.default.post(name: Notification.Name("dm.templates.changed"), object: nil)
                // Create Series for any frequency using rule-driven scheduling
                let cal = Calendar.current
                let starts = cal.startOfDay(for: startsOn)
                let series = Series(templateId: template.id, ownerId: userId, startsOn: starts, endsOn: {
                    if case .onDate(let d) = endRule { return cal.startOfDay(for: d) }
                    return nil
                }(), timezoneIdentifier: timezoneIdentifier, status: "active", lastGeneratedAt: nil, intervalWeeks: interval, anchorWeekday: selectedWeekdays.sorted().first, rule: buildRule())
                // If not weekly, keep legacy fields harmless (intervalWeeks/anchorWeekday) but rely on rule
                let serUC = try deps.resolve(type: SeriesUseCases.self)
                try await serUC.create(series)
                NotificationCenter.default.post(name: Notification.Name("dm.templates.changed"), object: nil)
            }
            // Trigger immediate sync to generate occurrences without delay
            if let sync = try? deps.resolve(type: SyncService.self) {
                _Concurrency.Task { await sync.sync(for: userId) }
            }
        } catch {
            Logger.shared.error("Failed to save template", category: .ui, error: error)
        }
    }

    // MARK: - Delete
    func deleteTemplateAndFutureInstances() async {
        guard let editing = editingTemplate else { return }
        do {
            let deps = Dependencies.shared
            let tplUC = try deps.resolve(type: TemplatesUseCases.self)
            // Soft-delete template locally
            var tombstoned = editing
            tombstoned.deletedAt = Date()
            tombstoned.updatedAt = Date()
            try await tplUC.update(tombstoned)
            // Mirror soft-delete remotely for cross-device visibility
            if let remoteTpl = try? Dependencies.shared.resolve(type: RemoteTemplatesRepository.self) {
                try? await remoteTpl.softDelete(id: editing.id)
            }
            // Pause/delete series if exists
            if var ser = existingSeries {
                let serUC = try deps.resolve(type: SeriesUseCases.self)
                ser.status = "paused"
                ser.deletedAt = Date()
                ser.updatedAt = Date()
                try await serUC.update(ser)
                if let remoteSer = try? Dependencies.shared.resolve(type: RemoteSeriesRepository.self) {
                    try? await remoteSer.softDelete(id: ser.id)
                }
            }
            // Delete future instances: all tasks under this template whose occurrenceDate >= today
            let tasksRepo = try deps.resolve(type: TasksRepository.self)
            let allTasks = try await tasksRepo.fetchTasks(for: userId, in: nil)
            let start = Calendar.current.startOfDay(for: Date())
            for task in allTasks where task.templateId == editing.id {
                let occurs = task.occurrenceDate ?? Date.distantPast
                if occurs >= start && task.deletedAt == nil {
                    try? await tasksRepo.deleteTask(by: task.id)
                }
            }
            if let sync = try? deps.resolve(type: SyncService.self) {
                _Concurrency.Task { await sync.sync(for: userId) }
            }
            NotificationCenter.default.post(name: Notification.Name("dm.templates.changed"), object: nil)
        } catch {
            Logger.shared.error("Failed to delete template and future instances", category: .ui, error: error)
        }
    }
    
    /// Deletes the template/series and removes all related tasks that are not completed (past and future)
    func deleteTemplateAndAllIncompleteInstances() async {
        guard let editing = editingTemplate else { return }
        do {
            let deps = Dependencies.shared
            let tplUC = try deps.resolve(type: TemplatesUseCases.self)
            // Soft-delete template locally
            var tombstoned = editing
            tombstoned.deletedAt = Date()
            tombstoned.updatedAt = Date()
            try await tplUC.update(tombstoned)
            // Mirror soft-delete remotely for cross-device visibility
            if let remoteTpl = try? Dependencies.shared.resolve(type: RemoteTemplatesRepository.self) {
                try? await remoteTpl.softDelete(id: editing.id)
            }
            // Pause/delete series if exists
            if var ser = existingSeries {
                let serUC = try deps.resolve(type: SeriesUseCases.self)
                ser.status = "paused"
                ser.deletedAt = Date()
                ser.updatedAt = Date()
                try await serUC.update(ser)
                if let remoteSer = try? Dependencies.shared.resolve(type: RemoteSeriesRepository.self) {
                    try? await remoteSer.softDelete(id: ser.id)
                }
            }
            // Delete all non-completed tasks related to this template (ignore already-deleted)
            let tasksRepo = try deps.resolve(type: TasksRepository.self)
            let allTasks = try await tasksRepo.fetchTasks(for: userId, in: nil)
            for task in allTasks where task.templateId == editing.id {
                if task.deletedAt == nil && task.isCompleted == false {
                    try? await tasksRepo.deleteTask(by: task.id)
                }
            }
            if let sync = try? deps.resolve(type: SyncService.self) {
                _Concurrency.Task { await sync.sync(for: userId) }
            }
            NotificationCenter.default.post(name: Notification.Name("dm.templates.changed"), object: nil)
        } catch {
            Logger.shared.error("Failed to delete template and all incomplete instances", category: .ui, error: error)
        }
    }
    
    // MARK: - Builders
    private func validateRecurrence() -> String? {
        switch frequency {
        case .daily: return interval < 1 ? "Interval must be ≥ 1" : nil
        case .weekly:
            if selectedWeekdays.isEmpty { return "Choose at least one weekday" }
            return nil
        case .monthly:
            if monthlyKind == .dayOfMonth && (monthDay < 1 || monthDay > 31) { return "Day must be 1–31" }
            return nil
        case .yearly:
            if yearlyKind == .dayOfMonth && (yearlyDay < 1 || yearlyDay > 31) { return "Day must be 1–31" }
            return nil
        }
    }
    
    private func buildRule() -> RecurrenceRule {
        let time = timeString()
        switch frequency {
        case .daily:
            return RecurrenceRule(freq: .daily, interval: interval, time: time)
        case .weekly:
            let codes = selectedWeekdays.sorted().compactMap { Self.weekdayCode($0) }
            return RecurrenceRule(freq: .weekly, interval: interval, byWeekday: codes, time: time)
        case .monthly:
            if monthlyKind == .dayOfMonth {
                return RecurrenceRule(freq: .monthly, interval: interval, byMonthDay: [monthDay], time: time)
            } else {
                let code = Self.weekdayCode(monthlyWeekday)
                return RecurrenceRule(freq: .monthly, interval: interval, byWeekday: code == nil ? nil : [code!], bySetPos: [monthlyOrdinal], time: time)
            }
        case .yearly:
            if yearlyKind == .dayOfMonth {
                return RecurrenceRule(freq: .yearly, interval: interval, byMonthDay: [yearlyDay], byMonth: [yearlyMonth], time: time)
            } else {
                let code = Self.weekdayCode(yearlyWeekday)
                return RecurrenceRule(freq: .yearly, interval: interval, byWeekday: code == nil ? nil : [code!], bySetPos: [yearlyOrdinal], byMonth: [yearlyMonth], time: time)
            }
        }
    }
    
    private func timeString() -> String? {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: defaultTime)
        guard let h = comps.hour, let m = comps.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }
    private func timeFromString(_ s: String) -> Date? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var comps = Calendar.current.dateComponents([.year,.month,.day], from: Date())
        comps.hour = h; comps.minute = m
        return Calendar.current.date(from: comps)
    }
    
    private func nextOccurrences(count: Int) -> [Date] {
        var results: [Date] = []
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: startsOn)
        // Seed: first is computed from anchor using recurrence engine step-by-step
        let rule = buildRule()
        var limit = 0
        while results.count < count && limit < 1000 {
            limit += 1
            if let next = recurrenceEngine.nextOccurrence(from: cursor, rule: rule, calendar: cal) {
                // Apply end rule
                if case .onDate(let endDate) = endRule, next > endDate { break }
                results.append(next)
                cursor = next
                if case .afterCount(let n) = endRule, results.count >= n { break }
            } else {
                break
            }
        }
        return results
    }
    
    private func buildSummary() -> String {
        let time = DateFormatter.localizedString(from: defaultTime, dateStyle: .none, timeStyle: .short)
        switch frequency {
        case .daily:
            return "Every \(interval == 1 ? "day" : "\(interval) days") at \(time) starting \(dateString(startsOn)) \(endClause())"
        case .weekly:
            let names = selectedWeekdays.sorted().map { Self.weekdayDisplayName($0) }.joined(separator: ", ")
            return "Every \(interval == 1 ? "week" : "\(interval) weeks") on \(names) at \(time) starting \(dateString(startsOn)) \(endClause())"
        case .monthly:
            if monthlyKind == .dayOfMonth {
                return "Every \(interval == 1 ? "month" : "\(interval) months") on day \(monthDay) at \(time) starting \(dateString(startsOn)) \(endClause())"
            } else {
                return "Every \(interval == 1 ? "month" : "\(interval) months") on \(ordinalName(monthlyOrdinal)) \(Self.weekdayDisplayName(monthlyWeekday)) at \(time) starting \(dateString(startsOn)) \(endClause())"
            }
        case .yearly:
            let monthName = DateFormatter().monthSymbols[(yearlyMonth - 1 + 12) % 12]
            if yearlyKind == .dayOfMonth {
                return "Every \(interval == 1 ? "year" : "\(interval) years") on \(monthName) \(yearlyDay) at \(time) starting \(dateString(startsOn)) \(endClause())"
            } else {
                return "Every \(interval == 1 ? "year" : "\(interval) years") on \(ordinalName(yearlyOrdinal)) \(Self.weekdayDisplayName(yearlyWeekday)) of \(monthName) at \(time) starting \(dateString(startsOn)) \(endClause())"
            }
        }
    }
    
    private func endClause() -> String {
        switch endRule {
        case .never: return ""
        case .onDate(let d): return "until \(dateString(d))"
        case .afterCount(let n): return "ending after \(n) occurrences"
        }
    }
    
    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
    
    // MARK: - Helpers
    static func weekdayDisplayName(_ weekday: Int) -> String {
        let cal = Calendar.current
        let i = (weekday - 1 + 7) % 7
        return cal.weekdaySymbols[i]
    }
    
    static func weekdayCode(_ weekday: Int) -> String? {
        switch weekday { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return nil }
    }
}

private extension Series {
    func withTemplateId(_ templateId: UUID, ownerId: UUID) -> Series {
        Series(id: self.id, templateId: templateId, ownerId: ownerId, startsOn: self.startsOn, endsOn: self.endsOn, timezoneIdentifier: self.timezoneIdentifier, status: self.status, lastGeneratedAt: self.lastGeneratedAt, intervalWeeks: self.intervalWeeks, anchorWeekday: self.anchorWeekday, createdAt: self.createdAt, updatedAt: self.updatedAt, deletedAt: self.deletedAt)
    }
}

private extension NewTemplateViewModel {
    /// Build Series only for weekly frequency to integrate with current generator
    func buildWeeklySeries(from start: Date) -> Series? {
        guard frequency == .weekly else { return nil }
        // Use earliest selected weekday as anchor; if none, fallback to start weekday
        let cal = Calendar.current
        let anchor: Int = selectedWeekdays.sorted().first ?? cal.component(.weekday, from: start)
        // Find first date from start that matches anchor
        var first = cal.startOfDay(for: start)
        while cal.component(.weekday, from: first) != anchor {
            if let next = cal.date(byAdding: .day, value: 1, to: first) { first = next } else { break }
        }
        let ends: Date? = {
            if case .onDate(let d) = endRule { return cal.startOfDay(for: d) }
            return nil
        }()
        return Series(templateId: UUID(), ownerId: userId, startsOn: first, endsOn: ends, timezoneIdentifier: timezoneIdentifier, status: "active", lastGeneratedAt: nil, intervalWeeks: interval, anchorWeekday: anchor)
    }
}


