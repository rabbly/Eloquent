import Foundation

/// Lightweight logging that can be toggled at runtime via `Settings.verboseLogging`.
/// Prefer `Log.verbose(...)` for chatty diagnostics.
enum Log {

    private static let verboseKey = "Eloquent.VerboseLogging"

    /// Emitted only when the user turns on verbose logging.
    /// Cheap when off: the message closure is not evaluated.
    @inline(__always)
    static func verbose(_ message: @autoclosure () -> String,
                        file: String = #file,
                        line: Int = #line) {
        guard UserDefaults.standard.bool(forKey: verboseKey) else { return }
        let filename = (file as NSString).lastPathComponent
        NSLog("[\(filename):\(line)] \(message())")
    }

    /// Always-on message for genuine errors and important events.
    @inline(__always)
    static func info(_ message: @autoclosure () -> String) {
        NSLog("%@", message())
    }
}
