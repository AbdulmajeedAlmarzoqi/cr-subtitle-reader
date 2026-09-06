import Foundation
import os

/// Diagnostics go to the unified log and to ~/Library/Logs/CR Subtitle Reader.log
/// (handy for bug reports; "Reveal Log" in Settings opens it).
enum Log {
    private static let logger = Logger(subsystem: "com.abdulmajeedalmarzoqi.crsubtitlereader", category: "app")
    private static let queue = DispatchQueue(label: "crsr.log")
    static let fileURL: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("CR Subtitle Reader.log")
    }()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        append("INFO  \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR \(message)")
    }

    private static func append(_ line: String) {
        let text = "\(formatter.string(from: Date())) \(line)\n"
        queue.async {
            guard let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
            // Keep the file small.
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > 2_000_000 {
                try? Data().write(to: fileURL)
            }
        }
    }
}
