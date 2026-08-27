import Darwin
import Foundation

public enum CrossProcessFileLockError: Error, Equatable, Sendable {
    case cannotOpen(Int32)
    case cannotLock(Int32)
}

/// A small advisory lock for coordinating read-modify-write operations between
/// the host app and Finder extension. `flock` is released automatically if a
/// process exits, avoiding stale lock files.
public enum CrossProcessFileLock {
    public static func withLock<Result>(
        at url: URL,
        _ operation: () throws -> Result
    ) throws -> Result {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw CrossProcessFileLockError.cannotOpen(errno)
        }
        defer { Darwin.close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CrossProcessFileLockError.cannotLock(errno)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try operation()
    }
}
