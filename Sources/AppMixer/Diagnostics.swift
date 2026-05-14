import Foundation

/// Appends to /tmp/appmixer.log (and the unified log) so behaviour can be
/// inspected regardless of how the app was launched.
func appLog(_ message: String) {
    NSLog(message)
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/appmixer.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: url)
    }
}
