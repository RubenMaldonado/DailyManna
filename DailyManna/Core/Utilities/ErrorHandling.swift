//
//  ErrorHandling.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

enum AppError: Error, LocalizedError {
    case unknown
    case custom(String)
    case underlying(Error)
    
    var errorDescription: String? {
        switch self {
        case .unknown: return "An unknown error occurred."
        case .custom(let message): return message
        case .underlying(let error): return error.localizedDescription
        }
    }
}

final class ErrorHandler {
    static let shared = ErrorHandler()
    
    private init() {}
    
    func handle(_ error: Error, context: String = "") {
        Logger.shared.error("Handled error in context: \(context)", error: error)
        // In a real app, you might send this to an analytics service (e.g., Sentry, Crashlytics)
        // or display a user-friendly alert.
        // For now, we just log it.
    }
    
    func wrap<T>(
        _ operation: () throws -> T,
        context: String = "",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> Result<T, Error> {
        do {
            return .success(try operation())
        } catch {
            let fullContext = "\(context) (File: \(file), Function: \(function), Line: \(line))"
            handle(error, context: fullContext)
            return .failure(error)
        }
    }
    
    func wrapAsync<T>(
        _ operation: () async throws -> T,
        context: String = "",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            let fullContext = "\(context) (File: \(file), Function: \(function), Line: \(line))"
            handle(error, context: fullContext)
            return .failure(error)
        }
    }
}

extension Result where Failure == Error {
    /// Creates a failure result with error handling
    static func handleError(_ error: Error, context: String = "") -> Result<Success, Error> {
        ErrorHandler.shared.handle(error, context: context)
        return .failure(error)
    }
}
