#if DEBUG
import Foundation

/// Operation-local diagnostics; never persisted to configuration or normal logs.
final class DebugJSONExportDiagnostics {
    private(set) var issues: [String] = []
    func record(_ issue: String) { issues.append(issue) }
}

/// File-only operations; never touches configuration or recovery storage.
enum DebugCloudJSONFile {
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DebugCloudJSON", isDirectory: true)
    }

    static func fileName(scope: String, name: String, date: Date, timeZone: TimeZone = .current) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Bound UTF-8 length, including multibyte names, below filesystem limits.
        var component = ""
        for character in cleaned {
            guard component.utf8.count + String(character).utf8.count <= 120 else { break }
            component.append(character)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSSZ"
        return "\(scope)_\(component.isEmpty ? scope : component)_\(formatter.string(from: date)).json"
    }

    static func write(payload: [String: Any], scope: String, name: String, date: Date,
                      directory: URL = root) throws -> URL {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(fileName(scope: scope, name: name, date: date))
        do {
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func remove(_ file: URL) {
        guard file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    static func cleanExpired(now: Date = Date(), directory: URL = root) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
        for file in files {
            guard UUID(uuidString: file.lastPathComponent) != nil,
                  let values = try? file.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]),
                  values.isDirectory == true, let created = values.creationDate,
                  now.timeIntervalSince(created) > 24 * 60 * 60 else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
#endif
