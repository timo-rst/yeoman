import Foundation
import Darwin

/// Descriptor-relative I/O. Does not claim isolation from arbitrary same-UID code.
public final class SecureDirectory {
    public let url: URL
    public let descriptor: Int32
    public init(_ url: URL, create: Bool = true) throws {
        self.url = url
        if create && mkdir(url.path, 0o700) != 0 && errno != EEXIST { throw Self.failure() }
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure() }
        do { try Self.validate(fd, directory: true); guard fchmod(fd, 0o700) == 0 else { throw Self.failure() } }
        catch { close(fd); throw error }
        descriptor = fd
    }
    private init(url: URL, descriptor: Int32) throws {
        self.url = url
        self.descriptor = descriptor
        do { try Self.validate(descriptor, directory: true); guard fchmod(descriptor, 0o700) == 0 else { throw Self.failure() } }
        catch { close(descriptor); throw error }
    }
    deinit { close(descriptor) }
    public static func name(_ name: String) throws {
        guard !name.isEmpty, name.utf8.count <= 240, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.utf8.contains(0) else { throw failure() }
    }
    public func child(_ name: String, create: Bool = true) throws -> SecureDirectory {
        try Self.name(name)
        if create && mkdirat(descriptor, name, 0o700) != 0 && errno != EEXIST { throw Self.failure() }
        let fd = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure() }
        return try SecureDirectory(url: url.appendingPathComponent(name), descriptor: fd)
    }
    public func exists(_ name: String) throws -> Bool {
        try Self.name(name)
        var info = stat()
        if fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        if errno == ENOENT { return false }
        throw Self.failure()
    }
    public func read(_ name: String, limit: Int) throws -> Data {
        try Self.name(name)
        let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure() }
        defer { close(fd) }
        try Self.validate(fd, directory: false)
        guard fchmod(fd, 0o600) == 0 else { throw Self.failure() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0, info.st_size <= limit else { throw Self.failure() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n == 0 { return data }
            if n < 0 { if errno == EINTR { continue }; throw Self.failure() }
            guard n <= limit - data.count else { throw Self.failure() }
            data.append(buffer, count: n)
        }
    }
    public func write(_ data: Data, name: String) throws {
        try Self.name(name)
        let temporary = ".write-" + UUID().uuidString
        let fd = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.failure() }
        defer { close(fd); unlinkat(descriptor, temporary, 0) }
        try Self.validate(fd, directory: false)
        try data.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: written), raw.count - written)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Self.failure() }
                written += n
            }
        }
        guard fsync(fd) == 0, renameat(descriptor, temporary, descriptor, name) == 0,
              fsync(descriptor) == 0 else { throw Self.failure() }
    }
    public func remove(_ name: String) throws {
        try Self.name(name)
        if unlinkat(descriptor, name, 0) != 0 && errno != ENOENT { throw Self.failure() }
    }
    /// Removes only verified regular files from this directory. Any link,
    /// subdirectory, foreign owner, hard link or undecodable name fails closed.
    public func purgeRegularFiles() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        for name in names {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
                throw Self.failure()
            }
            let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw Self.failure() }
            do { try Self.validate(fd, directory: false) }
            catch { close(fd); throw error }
            close(fd)
            guard unlinkat(descriptor, name, 0) == 0 else { throw Self.failure() }
        }
        guard fsync(descriptor) == 0 else { throw Self.failure() }
    }
    public static func validate(_ fd: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else { throw failure() }
        errno = 0
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            // Darwin reports ENOENT when a file has no extended ACL.
            guard errno == ENOENT else { throw failure() }
            return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        // Reject extended ACLs rather than silently accepting inherited grants.
        guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) != 0 else { throw failure() }
    }
    public static func temporary() throws -> SecureDirectory {
        var bytes = Array((FileManager.default.temporaryDirectory.path + "/yeoman-XXXXXX").utf8CString)
        guard let path = mkdtemp(&bytes) else { throw failure() }
        let url = URL(fileURLWithPath: String(cString: path))
        do { return try SecureDirectory(url, create: false) }
        catch { rmdir(url.path); throw error }
    }
    public static func readExternal(_ url: URL, limit: Int) throws -> Data {
        guard url.isFileURL else { throw failure() }
        let components = url.path.split(separator: "/").map(String.init)
        guard let last = components.last else { throw failure() }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw failure() }
        defer { close(parent) }
        for component in components.dropLast() {
            try name(component)
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw failure() }
            close(parent); parent = next
        }
        try name(last)
        let fd = openat(parent, last, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw failure() }
        defer { close(fd) }
        try validate(fd, directory: false)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0, info.st_size <= limit else { throw failure() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n == 0 { return data }
            if n < 0 && errno == EINTR { continue }
            guard n > 0, n <= limit - data.count else { throw failure() }
            data.append(buffer, count: n)
        }
    }
    private static func failure() -> Error { SecurityFailure.rejected("Unsicherer Dateizugriff oder Speicherfehler (\(errno)).") }
}
