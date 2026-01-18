import Foundation
import Foundation
import os.log

/// Centralized logging for the application
extension Logger {
    private static let subsystem = "com.decappub.app"
    
    /// Logger for network-related operations
    static let network = Logger(subsystem: subsystem, category: "network")
    
    /// Logger for photo library and image operations
    static let photos = Logger(subsystem: subsystem, category: "photos")
    
    /// Logger for data persistence operations
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    
    /// Logger for UI-related events
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// Logger for security-related events
    static let security = Logger(subsystem: subsystem, category: "security")
    
    /// Logger for memory and performance monitoring
    static let performance = Logger(subsystem: subsystem, category: "performance")
}

/// Logging utilities
struct AppLogger {
    
    /// Log a network request with sensitive data redacted
    static func logRequest(_ request: URLRequest) {
        let redacted = NetworkManager.redactedDescription(of: request)
        Logger.network.debug("\(redacted, privacy: .public)")
    }
    
    /// Log a network response
    static func logResponse(_ response: URLResponse?, data: Data?) {
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.network.debug("Response: Non-HTTP response")
            return
        }
        
        let statusCode = httpResponse.statusCode
        let dataSize = data?.count ?? 0
        Logger.network.debug("Response: \(statusCode) (\(dataSize) bytes)")
    }
    
    /// Log an error with privacy
    static func logError(_ error: Error, category: Logger = .network, context: String = "") {
        let contextString = context.isEmpty ? "" : "[\(context)] "
        Logger.network.error("\(contextString, privacy: .public)Error: \(error.localizedDescription, privacy: .public)")
    }
    
    /// Log memory usage
    static func logMemoryUsage() {
        let usedMemory = reportMemory()
        Logger.performance.info("Memory usage: \(usedMemory, privacy: .public) MB")
    }
    
    /// Report current memory usage in MB
    private static func reportMemory() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return "Unknown"
        }
        
        let usedMemory = Float(info.resident_size) / (1024 * 1024)
        return String(format: "%.1f", usedMemory)
    }
}

// MARK: - Mach Imports

import Darwin.Mach
