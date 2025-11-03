import Foundation

enum WorkingLogMarkdownExporter {
    static func generate(
        rangeStart: Date,
        rangeEnd: Date,
        itemsByDay: [(day: Date, tasks: [Task], notes: [WorkingLogItem])],
        labelsByTaskId: [UUID: [Label]] = [:]
    ) -> String {
        var lines: [String] = []
        let headerFmt = DateFormatter()
        headerFmt.dateFormat = "MMM dd, yyyy"
        lines.append("# Working Log (\(headerFmt.string(from: rangeStart)) – \(headerFmt.string(from: rangeEnd)))")
        lines.append("")
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE, MMM d"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let dateTimeFmt = DateFormatter()
        dateTimeFmt.dateFormat = "MMM d, yyyy HH:mm"
        for (day, tasks, notes) in itemsByDay {
            lines.append("## \(dayFmt.string(from: day))")
            if !tasks.isEmpty {
                lines.append("### Tasks")
                for t in tasks.sorted(by: { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }) {
                    let ts = t.completedAt != nil ? timeFmt.string(from: t.completedAt!) : "--:--"
                    lines.append("- [\(ts)] \(t.title)")
                    var meta: [String] = []
                    if let desc = t.description?.trimmingCharacters(in: .whitespacesAndNewlines), desc.isEmpty == false {
                        meta.append("Description: \(desc)")
                    }
                    let labels = (labelsByTaskId[t.id] ?? []).map { $0.name }.sorted()
                    if labels.isEmpty == false {
                        meta.append("Labels: \(labels.joined(separator: ", "))")
                    }
                    meta.append("Created: \(dateTimeFmt.string(from: t.createdAt))")
                    if let completed = t.completedAt {
                        meta.append("Completed: \(dateTimeFmt.string(from: completed))")
                    }
                    for m in meta {
                        lines.append("  - \(m)")
                    }
                }
            }
            if !notes.isEmpty {
                lines.append("### Log Items")
                for n in notes.sorted(by: { $0.occurredAt > $1.occurredAt }) {
                    let ts = timeFmt.string(from: n.occurredAt)
                    lines.append("- [\(ts)] \(n.title) — \(n.description)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    
    static func saveToDefaultLocation(filename: String, contents: String) throws -> URL {
        #if os(macOS)
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        #else
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        #endif
        let url = directory.appendingPathComponent(filename)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }
}


