import Foundation

/// Reads metadata for a directory entry without following its final symbolic
/// link. `FileManager.fileExists` follows links and therefore reports a valid,
/// movable broken link as missing.
enum FileSystemItemInspector {
    static func type(
        at url: URL,
        fileManager: FileManager = .default
    ) -> FileAttributeType? {
        guard url.isFileURL,
              let attributes = try? fileManager.attributesOfItem(
                atPath: url.standardizedFileURL.path
              ) else {
            return nil
        }
        return attributes[.type] as? FileAttributeType
    }

    static func exists(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        type(at: url, fileManager: fileManager) != nil
    }
}
