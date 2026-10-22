import Foundation
import Darwin
import CArchive

/// libarchive parses ZIP; all output is written through our descriptor-relative
/// writer. No archive_write_disk, extraction shell, links, or special files.
public enum SafeArchive {
    public struct Limits {
        public var entries = 10_000
        public var fileBytes = 128 * 1_048_576
        public var totalBytes = 512 * 1_048_576
        public var seconds: TimeInterval = 30
        public init() {}
    }
    public static func components(_ path: String) throws -> [String] {
        guard path.utf8.count <= 4096, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.utf8.contains(0) else { throw SecurityFailure.rejected("Ungültiger Archivpfad.") }
        let cleaned = path.hasSuffix("/") ? String(path.dropLast()) : path
        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= 32, parts.first == "Yeoman.app" else {
            throw SecurityFailure.rejected("Archiv muss ausschließlich Yeoman.app enthalten.")
        }
        for part in parts { try SecureDirectory.name(part) }
        return parts
    }
    public static func extract(archiveURL: URL, to root: SecureDirectory, limits: Limits = Limits()) throws {
        let fd = Darwin.open(archiveURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SecurityFailure.rejected("Archiv nicht lesbar.") }
        defer { close(fd) }
        try SecureDirectory.validate(fd, directory: false)
        // libarchive normalizes some ZIP external attributes (e.g. FIFO -> regular).
        // Inspect original central/local headers as well so policy is enforced on
        // the archive's declarations, not only the parser's normalized entries.
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var raw = Data()
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            guard chunk.count <= 128 * 1_048_576 - raw.count else { throw SecurityFailure.rejected("ZIP zu groß.") }
            raw.append(chunk)
        }
        try ZIPHeaderPolicy.validate(raw, limits: limits)
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw SecurityFailure.rejected("ZIP nicht seekbar.") }
        raw = Data()
        guard let reader = archive_read_new() else { throw SecurityFailure.rejected("Archivleser fehlt.") }
        defer { archive_read_free(reader) }
        guard archive_read_support_format_zip(reader) == 0,
              archive_read_open_fd(reader, fd, 65536) == 0 else { throw SecurityFailure.rejected("Ungültiges ZIP.") }
        let start = ProcessInfo.processInfo.systemUptime
        var seen = Set<String>(), directoryPrefixes = [String: String](), total = 0, count = 0
        var entry: OpaquePointer?
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            guard ProcessInfo.processInfo.systemUptime - start < limits.seconds else { throw SecurityFailure.rejected("Entpackzeit überschritten.") }
            let status = archive_read_next_header(reader, &entry)
            if status == 1 { break }
            guard status == 0, let entry, let rawPath = archive_entry_pathname(entry),
                  let path = String(validatingUTF8: rawPath), archive_entry_symlink(entry) == nil,
                  archive_entry_hardlink(entry) == nil, archive_entry_is_encrypted(entry) == 0 else {
                throw SecurityFailure.rejected("Ungültiger oder verlinkter Archiveintrag.")
            }
            let parts = try components(path)
            let canonical = parts.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
            count += 1
            guard count <= limits.entries, seen.insert(canonical).inserted else { throw SecurityFailure.rejected("Doppelter Archivpfad oder zu viele Dateien.") }
            let mode = archive_entry_mode(entry), kind = mode & S_IFMT
            guard kind == S_IFREG || kind == S_IFDIR else { throw SecurityFailure.rejected("Sonderdatei im Archiv.") }
            // Verify consistent casing across all directory components (AUD-10)
            for i in 1..<parts.count {
                let prefixExact = parts.prefix(i).joined(separator: "/")
                let prefixCanonical = prefixExact.precomposedStringWithCanonicalMapping.lowercased()
                if let existing = directoryPrefixes[prefixCanonical] {
                    guard existing == prefixExact else { throw SecurityFailure.rejected("Mehrdeutige Groß-/Kleinschreibung im Verzeichnispfad.") }
                } else {
                    directoryPrefixes[prefixCanonical] = prefixExact
                }
            }
            if kind == S_IFDIR {
                let dirExact = parts.joined(separator: "/")
                let dirCanonical = dirExact.precomposedStringWithCanonicalMapping.lowercased()
                if let existing = directoryPrefixes[dirCanonical] {
                    guard existing == dirExact else { throw SecurityFailure.rejected("Mehrdeutige Groß-/Kleinschreibung im Verzeichnispfad.") }
                } else {
                    directoryPrefixes[dirCanonical] = dirExact
                }
            }
            var parent = root
            for part in parts.dropLast() { parent = try parent.child(part) }
            let name = parts.last!
            if kind == S_IFDIR { _ = try parent.child(name); continue }
            let expected = archive_entry_size(entry)
            guard expected >= 0, expected <= limits.fileBytes else { throw SecurityFailure.rejected("Archivdatei zu groß.") }
            // Bounded per-entry buffering also lets us reject malformed data before committing it.
            var data = Data()
            while true {
                guard ProcessInfo.processInfo.systemUptime - start < limits.seconds else { throw SecurityFailure.rejected("Entpackzeit überschritten.") }
                let n = archive_read_data(reader, &buffer, buffer.count)
                if n == 0 { break }
                guard n > 0, n <= limits.fileBytes - data.count, n <= limits.totalBytes - total else {
                    throw SecurityFailure.rejected("Archiv beschädigt oder Entpackgrenze überschritten.")
                }
                data.append(buffer, count: n); total += n
            }
            guard data.count == expected, !(try parent.exists(name)) else { throw SecurityFailure.rejected("Mehrdeutiger Archiveintrag.") }
            try parent.write(data, name: name)
            if mode & 0o111 != 0 {
                let output = openat(parent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard output >= 0 else { throw SecurityFailure.rejected("Dateirechte nicht setzbar.") }
                defer { close(output) }
                try SecureDirectory.validate(output, directory: false)
                guard fchmod(output, 0o700) == 0 else { throw SecurityFailure.rejected("Dateirechte nicht setzbar.") }
            }
        }
        guard count > 0 else { throw SecurityFailure.rejected("Leeres Archiv.") }
    }
}

/// Deliberately narrow ZIP profile used by our release packager. Decompression
/// remains in the system libarchive implementation. ZIP64/SFX/encrypted archives
/// and alternate-path extra fields are unsupported and rejected.
public enum ZIPHeaderPolicy {
    public static func validate(_ data: Data, limits: SafeArchive.Limits = .init()) throws {
        func fail() -> Error { SecurityFailure.rejected("Nicht unterstützte oder widersprüchliche ZIP-Struktur.") }
        func number(_ offset: Int, _ size: Int) throws -> Int {
            guard offset >= 0, size <= data.count - offset else { throw fail() }
            return (0..<size).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        func bytes(_ offset: Int, _ length: Int) throws -> Data {
            guard offset >= 0, offset <= data.count, length >= 0, length <= data.count - offset else { throw fail() }
            return data.subdata(in: offset..<(offset + length))
        }
        func extras(_ offset: Int, _ length: Int) throws {
            var position = offset
            let end = offset + length
            guard end <= data.count else { throw fail() }
            while position < end {
                guard end - position >= 4 else { throw fail() }
                let kind = try number(position, 2), count = try number(position + 2, 2)
                guard [0x5455, 0x7875].contains(kind), count <= end - position - 4 else { throw fail() }
                position += 4 + count
            }
        }
        guard data.count >= 22 else { throw fail() }
        var endRecord: Int?
        for position in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try number(position, 4) == 0x06054b50,
               position + 22 + (try number(position + 20, 2)) == data.count { endRecord = position; break }
        }
        guard let end = endRecord, try number(end + 4, 2) == 0, (try number(end + 6, 2)) == 0 else { throw fail() }
        let count = try number(end + 10, 2), centralSize = try number(end + 12, 4), centralStart = try number(end + 16, 4)
        guard count > 0, count < 65535, count <= limits.entries, try number(end + 8, 2) == count,
              centralStart <= end, centralSize == end - centralStart else { throw fail() }
        var position = centralStart, total = 0, paths = Set<String>(), directoryPrefixes = [String: String](), regions: [Range<Int>] = []
        for _ in 0..<count {
            guard try number(position, 4) == 0x02014b50 else { throw fail() }
            let flags = try number(position + 8, 2), method = try number(position + 10, 2)
            let crc = try number(position + 16, 4), compressed = try number(position + 20, 4), size = try number(position + 24, 4)
            let nameSize = try number(position + 28, 2), extraSize = try number(position + 30, 2), commentSize = try number(position + 32, 2)
            let attributes = try number(position + 38, 4), local = try number(position + 42, 4)
            let mode = attributes >> 16, kind = mode & Int(S_IFMT)
            guard flags & ~0x080e == 0, [0, 8].contains(method),
                  [0, Int(S_IFREG), Int(S_IFDIR)].contains(kind),
                  size <= limits.fileBytes, size <= limits.totalBytes - total,
                  try number(position + 34, 2) == 0 else { throw fail() }
            total += size
            let name = try bytes(position + 46, nameSize)
            guard let path = String(data: name, encoding: .utf8) else { throw fail() }
            let components = try SafeArchive.components(path)
            let canonicalPath = components.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
            guard paths.insert(canonicalPath).inserted else { throw fail() }
            // Verify consistent casing across all directory components (AUD-10)
            for i in 1..<components.count {
                let prefixExact = components.prefix(i).joined(separator: "/")
                let prefixCanonical = prefixExact.precomposedStringWithCanonicalMapping.lowercased()
                if let existing = directoryPrefixes[prefixCanonical] {
                    guard existing == prefixExact else { throw fail() }
                } else {
                    directoryPrefixes[prefixCanonical] = prefixExact
                }
            }
            if kind == Int(S_IFDIR) {
                let dirExact = components.joined(separator: "/")
                let dirCanonical = dirExact.precomposedStringWithCanonicalMapping.lowercased()
                if let existing = directoryPrefixes[dirCanonical] {
                    guard existing == dirExact else { throw fail() }
                } else {
                    directoryPrefixes[dirCanonical] = dirExact
                }
            }
            try extras(position + 46 + nameSize, extraSize)
            guard local < centralStart, try number(local, 4) == 0x04034b50,
                  (try number(local + 6, 2)) == flags, (try number(local + 8, 2)) == method,
                  (try number(local + 26, 2)) == nameSize, (try bytes(local + 30, nameSize)) == name else { throw fail() }
            let localExtra = try number(local + 28, 2)
            try extras(local + 30 + nameSize, localExtra)
            var finish = local + 30 + nameSize + localExtra + compressed
            guard finish <= centralStart else { throw fail() }
            if flags & 8 == 0 {
                guard try number(local + 14, 4) == crc, (try number(local + 18, 4)) == compressed,
                      (try number(local + 22, 4)) == size else { throw fail() }
            } else {
                if try number(finish, 4) == 0x08074b50 { finish += 4 }
                guard try number(finish, 4) == crc, (try number(finish + 4, 4)) == compressed,
                      (try number(finish + 8, 4)) == size else { throw fail() }
                finish += 12
            }
            guard finish <= centralStart else { throw fail() }
            let region = local..<finish
            guard !regions.contains(where: { $0.overlaps(region) }) else { throw fail() }
            regions.append(region)
            position += 46 + nameSize + extraSize + commentSize
            guard position <= end else { throw fail() }
        }
        guard position == end else { throw fail() }
        // No hidden leading/trailing local records that a second ZIP parser could see.
        var consumed = 0
        for region in regions.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard region.lowerBound == consumed else { throw fail() }; consumed = region.upperBound
        }
        guard consumed == centralStart else { throw fail() }
    }
}
