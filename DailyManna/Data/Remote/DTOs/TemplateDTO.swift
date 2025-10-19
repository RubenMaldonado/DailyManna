import Foundation

struct TemplateDTO: Codable {
    let id: UUID
    let owner_id: UUID
    let name: String
    let description: String?
    let labels_default: [UUID]
    let checklist_default: [String]
    let default_bucket: String
    let default_due_time: String? // HH:mm
    let priority: String?
    let default_duration_min: Int?
    let status: String
    let version: Int
    let end_after_count: Int?
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
}

extension TemplateDTO {
    static func from(domain: Template) -> TemplateDTO {
        let hhmm: String? = {
            guard let comps = domain.defaultDueTime, let h = comps.hour, let m = comps.minute else { return nil }
            return String(format: "%02d:%02d", h, m)
        }()
        return TemplateDTO(
            id: domain.id,
            owner_id: domain.ownerId,
            name: domain.name,
            description: domain.description,
            labels_default: domain.labelsDefault,
            checklist_default: domain.checklistDefault,
            default_bucket: domain.defaultBucket.rawValue,
            default_due_time: hhmm,
            priority: domain.priority.rawValue,
            default_duration_min: domain.defaultDurationMinutes,
            status: domain.status,
            version: domain.version,
            end_after_count: domain.endAfterCount,
            created_at: domain.createdAt,
            updated_at: domain.updatedAt,
            deleted_at: domain.deletedAt
        )
    }
    
    func toDomain() -> Template {
        let comps: DateComponents? = {
            guard let s = default_due_time else { return nil }
            let parts = s.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) { return DateComponents(hour: h, minute: m) }
            return nil
        }()
        return Template(
            id: id,
            ownerId: owner_id,
            name: name,
            description: description,
            labelsDefault: labels_default,
            checklistDefault: checklist_default,
            defaultBucket: TimeBucket(rawValue: default_bucket) ?? .routines,
            defaultDueTime: comps,
            priority: TaskPriority(rawValue: priority ?? TaskPriority.normal.rawValue) ?? .normal,
            defaultDurationMinutes: default_duration_min,
            status: status,
            version: version,
            endAfterCount: end_after_count,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at
        )
    }
}


