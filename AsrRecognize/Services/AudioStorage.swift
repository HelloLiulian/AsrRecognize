import Foundation

enum AudioStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func makeNewFileURL() -> URL {
        directory.appendingPathComponent("\(UUID().uuidString).caf")
    }

    static func makeImportedFileURL(extension ext: String) -> URL {
        let suffix = ext.isEmpty ? "audio" : ext.lowercased()
        return directory.appendingPathComponent("\(UUID().uuidString).\(suffix)")
    }

    static func delete(named fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
