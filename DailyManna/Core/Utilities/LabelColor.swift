//
//  LabelColor.swift
//  DailyManna
//
//  Deterministic color hashing for labels.
//

import Foundation

enum LabelColorHash {
    static func colorHex(for name: String) -> String {
        let palette = Colors.labelPalette
        guard palette.isEmpty == false else { return "#3B82F6" }
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hasher = Hasher()
        hasher.combine(lowered)
        let value = hasher.finalize()
        let idx = abs(value) % palette.count
        return palette[idx]
    }
}



