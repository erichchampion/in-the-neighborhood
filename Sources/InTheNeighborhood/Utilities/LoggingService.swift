import Foundation
import OSLog

/// Shared logging service with log levels and build configuration support
/// - In Debug builds: Logs all messages (error, warning, info, debug)
/// - In Release builds: Only logs error messages
final class LoggingService: @unchecked Sendable {
    /// Shared instance
    static let shared = LoggingService()
    
    /// Subsystem identifier for all logs
    private static let subsystem = "com.in-the-neighborhood"
    
    /// Determine if we're in a debug build
    #if DEBUG
    private let isDebugBuild = true
    #else
    private let isDebugBuild = false
    #endif
    
    private init() {}
    
    /// Log levels
    enum LogLevel {
        case error
        case warning
        case info
        case debug
        
        /// OSLog level corresponding to this log level
        var osLogType: OSLogType {
            switch self {
            case .error:
                return .error
            case .warning:
                return .default
            case .info:
                return .info
            case .debug:
                return .debug
            }
        }
    }
    
    /// Create a logger for a specific category
    /// - Parameter category: Category name (e.g., "LLMModelDownload", "LlamaCppService")
    /// - Returns: Logger instance for the category
    func logger(for category: String) -> Logger {
        return Logger(subsystem: Self.subsystem, category: category)
    }
    
    /// Log a message with a specific level
    /// - Parameters:
    ///   - level: Log level (error, warning, info, debug)
    ///   - message: Message to log
    ///   - category: Category name
    ///   - file: Source file name (automatically captured)
    ///   - function: Function name (automatically captured)
    ///   - line: Line number (automatically captured)
    func log(
        _ level: LogLevel,
        _ message: String,
        category: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // In release builds, only log errors
        guard isDebugBuild || level == .error else {
            return
        }
        
        let logger = self.logger(for: category)
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        
        // Use appropriate OSLog method based on level
        switch level {
        case .error:
            logger.error("\(logMessage)")
        case .warning:
            logger.warning("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .debug:
            logger.debug("\(logMessage)")
        }
    }
    
    /// Log an error message
    func error(_ message: String, category: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, category: category, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    func warning(_ message: String, category: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, category: category, file: file, function: function, line: line)
    }
    
    /// Log an info message
    func info(_ message: String, category: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, category: category, file: file, function: function, line: line)
    }
    
    /// Log a debug message (only in debug builds)
    func debug(_ message: String, category: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, category: category, file: file, function: function, line: line)
    }
}
