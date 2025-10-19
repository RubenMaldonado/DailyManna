import Foundation

enum FeatureFlags {
    /// Gate for new routines templates/series weekly generation and propagation
    static var routinesTemplatesEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}


