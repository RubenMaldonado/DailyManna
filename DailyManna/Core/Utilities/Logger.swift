//
//  Logger.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import OSLog

enum LogCategory: String {
    case general = "General"
    case data = "Data"
    case domain = "Domain"
    case ui = "UI"
    case network = "Network"
    case sync = "Sync"
    case auth = "Auth"
}

final class Logger {
    static let shared = Logger()
    
    private let osLog: OSLog
    
    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.dailymanna", category: "App")
    }
    
    func log(_ message: String, category: LogCategory = .general, type: OSLogType = .default) {
        os_log("%{public}@", log: osLog, type: type, "[\(category.rawValue)] \(message)")
    }
    
    func debug(_ message: String, category: LogCategory = .general) {
        log(message, category: category, type: .debug)
    }
    
    func info(_ message: String, category: LogCategory = .general) {
        log(message, category: category, type: .info)
    }
    
    func error(_ message: String, category: LogCategory = .general, error: Error? = nil) {
        var fullMessage = message
        if let error {
            fullMessage += " Error: \(error.localizedDescription)"
        }
        log(fullMessage, category: category, type: .error)
    }
    
    func fault(_ message: String, category: LogCategory = .general, error: Error? = nil) {
        var fullMessage = message
        if let error {
            fullMessage += " Error: \(error.localizedDescription)"
        }
        log(fullMessage, category: category, type: .fault)
    }
}
