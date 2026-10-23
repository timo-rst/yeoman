import Foundation
import AppKit
import CryptoKit
import Darwin
import WebKit
import YeomanCore

private var defaultsSuites: [String] = []
func isolatedDefaults() -> UserDefaults {
    let name = "de.trst.Yeoman.tests." + UUID().uuidString
    defaultsSuites.append(name)
    return UserDefaults(suiteName: name)!
}
func removeTestDefaults() { for name in defaultsSuites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }

final class MemorySecrets: SecretStore {
    var values: [String: Data] = [:]
    var fails = false
    func read(_ account: String) throws -> Data? {
        if fails { throw SecurityFailure.rejected("test keychain failure") }; return values[account]
    }
    func write(_ data: Data, account: String) throws {
        if fails { throw SecurityFailure.rejected("test keychain failure") }; values[account] = data
    }
    func delete(_ account: String) throws {
        if fails { throw SecurityFailure.rejected("test keychain failure") }; values.removeValue(forKey: account)
    }
}
func rejects(_ block: () throws -> Void, file: String = #file, line: Int = #line) {
    do { try block(); TestHarness.shared.recordFailure("Expected rejection", file: file, line: line) } catch {}
}
func temporary(_ block: (SecureDirectory) throws -> Void) throws {
    let directory = try SecureDirectory.temporary()
    defer { try? FileManager.default.removeItem(at: directory.url) }
    try block(directory)
}
func pump(until predicate: () -> Bool, timeout: TimeInterval = 5) {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    assertTrue(predicate(), "Asynchronous operation timed out")
}

private final class FixtureProtocol: URLProtocol {
    static var status = 200
    static var chunks = [Data]()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for data in Self.chunks { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func fixtureDownload(status: Int = 200, chunks: [Data], limit: Int) -> Result<Data, Error> {
    FixtureProtocol.status = status; FixtureProtocol.chunks = chunks
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
    var outcome: Result<Data, Error>?
    Task { @MainActor in
        do { outcome = .success(try await UpdateDownload(limit: limit, apiRequest: true, configuration: config).fetch(URLRequest(url: UpdateURLPolicy.api))) }
        catch { outcome = .failure(error) }
    }
    pump { outcome != nil }
    return outcome ?? .failure(SecurityFailure.rejected("timeout"))
}

private func zipFixture(_ root: SecureDirectory, entries: [(String, String, Int)]) throws -> URL {
    let manifest = entries.map { ["name": $0.0, "data": $0.1, "mode": $0.2] as [String: Any] }
    try root.write(JSONSerialization.data(withJSONObject: manifest), name: "entries.json")
    let script = """
    import sys,json,zipfile
    with open(sys.argv[1]) as f: entries=json.load(f)
    with zipfile.ZipFile(sys.argv[2], 'w', compression=zipfile.ZIP_DEFLATED) as z:
      for e in entries:
        i=zipfile.ZipInfo(e['name']); i.create_system=3; i.external_attr=e['mode']<<16
        i.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(i,e['data'])
    """
    try root.write(Data(script.utf8), name: "zip.py")
    let archive = root.url.appendingPathComponent("fixture.zip")
    let result = try BoundedProcess.run("/usr/bin/python3", [root.url.appendingPathComponent("zip.py").path,
        root.url.appendingPathComponent("entries.json").path, archive.path], timeout: 10)
    guard result.status == 0 else { throw SecurityFailure.rejected("ZIP fixture generator failed") }
    return archive
}

func runSecurityTests() {
    let h = TestHarness.shared
    h.runSuite("Security: trust and downloads") {
        h.test("Unconfigured trust fails closed") {
            rejects { _ = try UpdateTrust.parseKey(from: "") }
            rejects { _ = try UpdateTrust.parseKey(from: "invalid-base64") }
            rejects { _ = try UpdateTrust.parseKey(from: Data(repeating: 1, count: 16).base64EncodedString()) }
            let validRaw = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
            _ = try UpdateTrust.parseKey(from: validRaw)
        }
        h.test("Release private keys stay outside the repository and require private permissions") {
            try temporary { root in
                let repository = root.url.appendingPathComponent("repo", isDirectory: true)
                try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: false)
                rejects { _ = try ReleaseKeyPolicy.externalPath(repository.appendingPathComponent("key").path, repository: repository) }
                let external = root.url.appendingPathComponent("private-key")
                try Data("fixture".utf8).write(to: external)
                assertEqual(chmod(external.path, 0o644), 0)
                rejects { try ReleaseKeyPolicy.validatePrivateFile(external) }
                assertEqual(chmod(external.path, 0o600), 0)
                try ReleaseKeyPolicy.validatePrivateFile(external)
            }
        }
        h.test("Strict release versions reject malformed and pre-release strings") {
            for raw in ["1.x.2", "1.2.3-beta", "1..2", "01.2.3", "-1.2.3", "1.2.3.4", "999999999999999999.2.3"] { assertNil(ReleaseVersion(raw)) }
            assertTrue(ReleaseVersion("1.2.4")! > ReleaseVersion("1.2.3")!)
        }
        h.test("Signed archive authenticates exact bytes, version and key") {
            let key = Curve25519.Signing.PrivateKey(), other = Curve25519.Signing.PrivateKey()
            let archive = Data("test archive".utf8)
            let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
            let metadata = SignedUpdate.Metadata(version: "1.2.3", size: archive.count, sha256: hash)
            let payload = try JSONEncoder().encode(metadata)
            let signed = SignedUpdate(payload: payload, signature: try key.signature(for: payload))
            let verified = try signed.verified(key: key.publicKey, current: "1.0.0")
            try SignedUpdate.verifyArchive(archive, metadata: verified)
            rejects { _ = try signed.verified(key: other.publicKey, current: "1.0.0") }
            rejects { _ = try signed.verified(key: key.publicKey, current: "1.2.3") }
            rejects { _ = try signed.verified(key: key.publicKey, current: "2.0.0") }
            rejects { try SignedUpdate.verifyArchive(Data("tampered".utf8), metadata: verified) }
            rejects { _ = try SignedUpdate(payload: payload + Data([0]), signature: signed.signature).verified(key: key.publicKey, current: "1.0.0") }
        }
        h.test("Initial URL policy rejects foreign repositories, subdomains, credentials, ports and DMG") {
            let prefix = "https://github.com/timo-rst/mac_customizer/releases/download/v1.2.3/"
            assertTrue(UpdateURLPolicy.asset(URL(string: prefix + "Yeoman.zip")!))
            for raw in [prefix + "Yeoman.dmg", prefix.replacingOccurrences(of: "timo-rst", with: "other") + "Yeoman.zip",
                        prefix.replacingOccurrences(of: "github.com", with: "evil.github.com") + "Yeoman.zip",
                        prefix.replacingOccurrences(of: "github.com", with: "u:p@github.com") + "Yeoman.zip",
                        prefix.replacingOccurrences(of: "github.com", with: "github.com:444") + "Yeoman.zip"] {
                assertFalse(UpdateURLPolicy.asset(URL(string: raw)!))
            }
            assertFalse(UpdateURLPolicy.releasePage(URL(string: "file:///tmp/test")!))
        }
        h.test("Redirects restrict hosts, counts and API authorization origin") {
            let cdn = URL(string: "https://release-assets.githubusercontent.com/test")!
            assertTrue(UpdateURLPolicy.redirect(cdn, apiRequest: false, count: 1))
            assertFalse(UpdateURLPolicy.redirect(cdn, apiRequest: true, count: 1))
            assertFalse(UpdateURLPolicy.redirect(cdn, apiRequest: false, count: 5))
            assertFalse(UpdateURLPolicy.redirect(URL(string: "https://objects.githubusercontent.com/test")!, apiRequest: false, count: 1))
            assertFalse(UpdateURLPolicy.redirect(URL(string: "https://github-releases.githubusercontent.com/test")!, apiRequest: false, count: 1))
            assertFalse(UpdateURLPolicy.redirect(URL(string: "https://127.0.0.1/test")!, apiRequest: false, count: 1))
            assertTrue(UpdateURLPolicy.releasePage(URL(string: "https://github.com/timo-rst/mac_customizer/releases/tag/v1.2.3")!))
            assertFalse(UpdateURLPolicy.releasePage(URL(string: "https://github.com/timo-rst/mac_customizer/releases/tag/v1.2.3/extra")!))
        }
        h.test("Streaming download succeeds without Content-Length") {
            let result = fixtureDownload(chunks: [Data("ab".utf8), Data("cd".utf8)], limit: 4)
            assertEqual(try result.get(), Data("abcd".utf8))
        }
        h.test("Streaming download enforces actual bytes and HTTP status") {
            rejects { _ = try fixtureDownload(chunks: [Data(repeating: 1, count: 100)], limit: 4).get() }
            rejects { _ = try fixtureDownload(status: 404, chunks: [], limit: 4).get() }
        }
        h.test("Bundle-ID forgery and wrong version do not authenticate code") {
            try temporary { root in
                let app = try root.child("Yeoman.app"), contents = try app.child("Contents")
                let plist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": "1.2.3", "CFBundleExecutable": "Yeoman"]
                try contents.write(PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), name: "Info.plist")
                rejects { try BundleVerifier.verify(app.url, version: "1.2.3") }
                rejects { try BundleVerifier.verify(app.url, version: "2.0.0") }
            }
        }
    }
    h.runSuite("Security: filesystem and archive") {
        h.test("Secure storage writes 0600 files in 0700 directories") {
            try temporary { root in
                try root.write(Data("fixture".utf8), name: "value")
                assertEqual(try root.read("value", limit: 7), Data("fixture".utf8))
                let attrs = try FileManager.default.attributesOfItem(atPath: root.url.path)
                assertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
                let fileAttrs = try FileManager.default.attributesOfItem(atPath: root.url.appendingPathComponent("value").path)
                assertEqual((fileAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
                rejects { _ = try root.read("value", limit: 1) }
            }
        }
        h.test("Traversal, symlinks, hard links and FIFOs are rejected") {
            try temporary { root in
                try root.write(Data("sentinel".utf8), name: "sentinel")
                for name in ["..", "/tmp/a", "a/b", "a\\b", ""] { rejects { _ = try root.read(name, limit: 100) } }
                let linked = root.url.appendingPathComponent("link")
                try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root.url.appendingPathComponent("sentinel"))
                rejects { _ = try root.read("link", limit: 100) }
                let fifo = root.url.appendingPathComponent("fifo").path
                assertEqual(mkfifo(fifo, 0o600), 0)
                rejects { _ = try root.read("fifo", limit: 100) }
                assertEqual(linkat(root.descriptor, "sentinel", root.descriptor, "hard", 0), 0)
                rejects { _ = try root.read("hard", limit: 100) }
            }
        }
        h.test("Legacy cache cleanup deletes only verified regular files") {
            try temporary { root in
                let cache = try root.child("favicons")
                try cache.write(Data("old".utf8), name: "icon_https___example.png")
                try cache.purgeRegularFiles()
                assertTrue(try FileManager.default.contentsOfDirectory(atPath: cache.url.path).isEmpty)
                try root.write(Data("sentinel".utf8), name: "sentinel")
                try FileManager.default.createSymbolicLink(at: cache.url.appendingPathComponent("link"),
                                                           withDestinationURL: root.url.appendingPathComponent("sentinel"))
                rejects { try cache.purgeRegularFiles() }
                assertEqual(try root.read("sentinel", limit: 16), Data("sentinel".utf8))
            }
        }
        h.test("Extended ACL fails closed") {
            try temporary { root in
                let child = try root.child("acl")
                let result = try BoundedProcess.run("/bin/chmod", ["+a", "everyone allow read,write", child.url.path])
                assertEqual(result.status, 0)
                rejects { _ = try SecureDirectory(child.url, create: false) }
            }
        }
        h.test("Valid ZIP extracts through descriptor-relative writer") {
            try temporary { root in
                let archive = try zipFixture(root, entries: [("Yeoman.app/Contents/test.txt", "fixture", 0o100600)])
                let extract = try root.child("extract")
                try SafeArchive.extract(archiveData: Data(contentsOf: archive), to: extract)
                let contents = try extract.child("Yeoman.app", create: false).child("Contents", create: false)
                assertEqual(try contents.read("test.txt", limit: 16), Data("fixture".utf8))
            }
        }
        h.test("Release packager ZIP profile is accepted") {
            try temporary { root in
                let app = try root.child("Yeoman.app"), contents = try app.child("Contents"), macOS = try contents.child("MacOS")
                try contents.write(Data("plist".utf8), name: "Info.plist")
                try macOS.write(Data("binary".utf8), name: "Yeoman")
                let archive = root.url.appendingPathComponent("release.zip")
                let zip = try BoundedProcess.run("/usr/bin/zip", ["-q", "-r", "-X", archive.path, "Yeoman.app"],
                                                 timeout: 10, currentDirectory: root.url)
                assertEqual(zip.status, 0)
                let extracted = try root.child("packager-extract")
                try SafeArchive.extract(archiveURL: archive, to: extracted)
                assertEqual(try extracted.child("Yeoman.app", create: false).child("Contents", create: false)
                    .read("Info.plist", limit: 16), Data("plist".utf8))
            }
        }
        for (label, entries) in [
            ("traversal", [("Yeoman.app/../outside", "x", 0o100600)]),
            ("absolute", [("/tmp/outside", "x", 0o100600)]),
            ("symlink app", [("Yeoman.app", "../outside", 0o120777)]),
            ("symlink component", [("Yeoman.app/link", "../../outside", 0o120777), ("Yeoman.app/link/file", "x", 0o100600)]),
            ("duplicate", [("Yeoman.app/a", "x", 0o100600), ("Yeoman.app/a", "y", 0o100600)]),
            ("case collision", [("Yeoman.app/a", "x", 0o100600), ("Yeoman.app/A", "y", 0o100600)]),
            ("parent case collision", [("Yeoman.app/Foo/a", "x", 0o100600), ("Yeoman.app/foo/b", "y", 0o100600)]),
            ("special file", [("Yeoman.app/fifo", "", 0o010600)])
        ] {
            h.test("ZIP rejects " + label) {
                try temporary { root in
                    let archive = try zipFixture(root, entries: entries)
                    let extract = try root.child("extract")
                    rejects { try SafeArchive.extract(archiveURL: archive, to: extract) }
                    assertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("outside").path))
                }
            }
        }
        h.test("Archive entry, byte and time limits are enforced") {
            try temporary { root in
                let archive = try zipFixture(root, entries: [("Yeoman.app/a", String(repeating: "x", count: 4096), 0o100600)])
                for index in 0..<4 {
                    var limits = SafeArchive.Limits()
                    switch index { case 0: limits.fileBytes = 4; case 1: limits.totalBytes = 4; case 2: limits.entries = 0; default: limits.seconds = 0 }
                    let dest = try root.child("extract-\(index)")
                    rejects { try SafeArchive.extract(archiveURL: archive, to: dest, limits: limits) }
                }
            }
        }
    }
    h.runSuite("Security: secrets and persistence") {
        h.test("Token migration removes defaults only after a successful secret-store write") {
            let defaults = isolatedDefaults(), keys = MemorySecrets()
            defaults.set("synthetic-token", forKey: "update_github_token")
            keys.fails = true
            rejects { _ = try SecretMigration.token(defaults: defaults, secrets: keys) }
            assertEqual(defaults.string(forKey: "update_github_token"), "synthetic-token")
            keys.fails = false
            assertEqual(try SecretMigration.token(defaults: defaults, secrets: keys), "synthetic-token")
            assertNil(defaults.string(forKey: "update_github_token"))
            try keys.delete("github-token"); assertNil(try keys.read("github-token"))
            defaults.set("bad\ntoken", forKey: "update_github_token")
            rejects { _ = try SecretMigration.token(defaults: defaults, secrets: keys) }
            assertEqual(defaults.string(forKey: "update_github_token"), "bad\ntoken")
        }
        h.test("SecureFileSecretStore writes 0600 keys in private directory and roundtrips") {
            try temporary { root in
                let secretsDir = root.url.appendingPathComponent(".secrets")
                let store = SecureFileSecretStore(directoryURL: secretsDir)
                let sampleKey = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                assertNil(try store.read("test-key"))
                try store.write(sampleKey, account: "test-key")
                assertEqual(try store.read("test-key"), sampleKey)
                try store.delete("test-key")
                assertNil(try store.read("test-key"))
            }
        }
        h.test("SecureFileSecretStore uses collision-free names and migrates known legacy files") {
            try temporary { root in
                let secretsDir = root.url.appendingPathComponent(".secrets")
                let store = SecureFileSecretStore(directoryURL: secretsDir)
                try store.write(Data("dot".utf8), account: "a.b")
                try store.write(Data("underscore".utf8), account: "a_b")
                assertEqual(try store.read("a.b"), Data("dot".utf8))
                assertEqual(try store.read("a_b"), Data("underscore".utf8))

                let directory = try SecureDirectory(secretsDir, create: false)
                try directory.write(Data("legacy-token".utf8), name: "github-token.key")
                assertEqual(try store.read("github-token"), Data("legacy-token".utf8))
                assertFalse(try directory.exists("github-token.key"))
                let names = try FileManager.default.contentsOfDirectory(atPath: secretsDir.path)
                assertTrue(names.contains(where: { $0.hasPrefix("v2-") && $0.hasSuffix(".key") }))
            }
        }
        h.test("SecureFileSecretStore rejects a symlinked Yeoman ancestor") {
            try temporary { root in
                let redirected = try root.child("redirected")
                let alias = root.url.appendingPathComponent("Yeoman")
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: redirected.url)
                let store = SecureFileSecretStore(directoryURL: alias.appendingPathComponent(".secrets"))
                rejects { try store.write(Data("secret".utf8), account: "github-token") }
                assertFalse(FileManager.default.fileExists(atPath: redirected.url.appendingPathComponent(".secrets").path))
            }
        }
        h.test("Authenticated encryption binds record identity and rejects tampering") {
            let cipher = try RecordCipher(key: Data(repeating: 7, count: 32))
            var encrypted = try cipher.seal(Data("synthetic-secret".utf8), record: "id1")
            assertEqual(try cipher.open(encrypted, record: "id1"), Data("synthetic-secret".utf8))
            rejects { _ = try cipher.open(encrypted, record: "id2") }
            encrypted[encrypted.count - 1] ^= 1
            rejects { _ = try cipher.open(encrypted, record: "id1") }
        }
        h.test("Missing key and invalid ciphertext never overwrite stored data") {
            try temporary { root in
                let keys = MemorySecrets()
                let doc = try EncryptedDocument(directory: root, name: "doc.enc", secrets: keys, limit: 100)
                try doc.write(Data("fixture".utf8))
                keys.values.removeAll()
                rejects { _ = try EncryptedDocument(directory: root, name: "doc.enc", secrets: keys, limit: 100) }
                try root.write(Data("tamper".utf8), name: "doc.enc")
                rejects { _ = try doc.read() }
                rejects { try doc.write(Data("replacement".utf8)) }
                assertEqual(try root.read("doc.enc", limit: 100), Data("tamper".utf8))
            }
        }
        h.test("Clipboard generation changes and markers reject capture") {
            assertTrue(ClipboardMonitor.acceptsSnapshot(before: 1, after: 1, sensitive: false))
            assertFalse(ClipboardMonitor.acceptsSnapshot(before: 1, after: 2, sensitive: false))
            assertFalse(ClipboardMonitor.acceptsSnapshot(before: 1, after: 1, sensitive: true))
            assertTrue(ClipboardMonitor.isTransientPasteboardType("org.nspasteboard.ConcealedType"))
        }
        h.test("Clipboard validator rejects paths, duplicate IDs, quotas and pinned excess") {
            var state = ClipboardSnapshot()
            let bad = ClipboardItem(content: "test", type: .image, imageFileName: "../outside")
            state.items = [bad]; rejects { try state.validate() }
            let item = ClipboardItem(content: "fixture", isPinned: true)
            state.items = [item, item]; rejects { try state.validate() }
            state.items = [ClipboardItem(content: String(repeating: "x", count: SecurityPolicy.textBytes + 1))]
            rejects { try state.validate() }
            state.items = (0..<501).map { ClipboardItem(content: String($0), isPinned: true) }
            rejects { try state.validate() }
        }
        h.test("Clipboard delete wins over queued older snapshots without plaintext files") {
            try temporary { root in
                let keys = MemorySecrets(), defaults = isolatedDefaults()
                let store = ClipboardHistoryStore(directory: root.url, secrets: keys, defaults: defaults)
                store.flushForTesting(); store.setPersistent(true); store.flushForTesting()
                for n in 0..<20 { store.addItem(content: "synthetic-secret-\(n)") }
                store.clearAll(); store.flushForTesting()
                let doc = try EncryptedDocument(directory: root, name: "clipboard-v1.enc", secrets: keys, limit: SecurityPolicy.historyBytes)
                let state = try JSONDecoder().decode(ClipboardSnapshot.self, from: doc.read()!)
                assertTrue(state.items.isEmpty)
                let raw = try root.read("clipboard-v1.enc", limit: SecurityPolicy.historyBytes)
                assertFalse(String(decoding: raw, as: UTF8.self).contains("synthetic-secret"))
                assertFalse(try root.exists("clipboard_history.json"))
            }
        }
        h.test("Clipboard file jobs cannot resurrect images after clear") {
            try temporary { root in
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let png = rep.representation(using: .png, properties: [:])!
                try root.write(png, name: "fixture.png")
                let store = ClipboardHistoryStore(directory: nil, secrets: MemorySecrets(), defaults: isolatedDefaults())
                store.flushForTesting()
                store.addItem(content: "before-clear")
                store.flushForTesting()
                pump { !store.items.isEmpty }
                store.addImageFile(root.url.appendingPathComponent("fixture.png").resolvingSymlinksInPath())
                store.clearAll()
                store.flushForTesting()
                pump { store.items.isEmpty }
                assertTrue(store.items.isEmpty)
            }
        }
        h.test("Clipboard legacy migration commits encryption before deleting source") {
            try temporary { root in
                let keys = MemorySecrets(), defaults = isolatedDefaults()
                try root.write(JSONEncoder().encode([ClipboardItem(content: "legacy-fixture")]), name: "clipboard_history.json")
                let store = ClipboardHistoryStore(directory: root.url, secrets: keys, defaults: defaults)
                store.flushForTesting()
                assertFalse(try root.exists("clipboard_history.json"))
                let doc = try EncryptedDocument(directory: root, name: "clipboard-v1.enc", secrets: keys, limit: SecurityPolicy.historyBytes)
                let snapshot = try JSONDecoder().decode(ClipboardSnapshot.self, from: doc.read()!)
                assertEqual(snapshot.items.first?.content, "legacy-fixture")
            }
        }
        h.test("Clipboard migration preserves unreferenced UUID-shaped image files") {
            try temporary { root in
                let keys = MemorySecrets(), defaults = isolatedDefaults()
                try root.write(JSONEncoder().encode([ClipboardItem(content: "legacy-fixture")]), name: "clipboard_history.json")
                let images = try root.child("clipboard_images")
                let orphan = UUID().uuidString + ".png"
                try images.write(Data("unrelated".utf8), name: orphan)
                let store = ClipboardHistoryStore(directory: root.url, secrets: keys, defaults: defaults)
                store.flushForTesting()
                assertFalse(try root.exists("clipboard_history.json"))
                assertEqual(try images.read(orphan, limit: 64), Data("unrelated".utf8))
            }
        }
        h.test("Failed secret store preserves legacy history") {
            try temporary { root in
                let keys = MemorySecrets(); keys.fails = true
                try root.write(JSONEncoder().encode([ClipboardItem(content: "legacy-fixture")]), name: "clipboard_history.json")
                let store = ClipboardHistoryStore(directory: root.url, secrets: keys, defaults: isolatedDefaults())
                store.flushForTesting(); store.clearAll(); store.flushForTesting()
                assertTrue(try root.exists("clipboard_history.json"))
                assertFalse(try root.exists("clipboard-v1.enc"))
            }
        }
    }
    h.runSuite("Security: process execution and identity") {
        h.test("Output larger than pipe capacity drains without deadlock") {
            let result = try BoundedProcess.run("/bin/dd", ["if=/dev/zero", "bs=65536", "count=16"], timeout: 5, limit: 2 * 1_048_576)
            assertEqual(result.status, 0); assertEqual(result.data.count, 1_048_576)
        }
        h.test("Stderr is drained and output limits and deadlines cancel owned children") {
            let result = try BoundedProcess.run("/bin/sh", ["-c", "/bin/dd if=/dev/zero bs=65536 count=16 >&2"], timeout: 5, limit: 2 * 1_048_576)
            assertEqual(result.status, 0)
            rejects { _ = try BoundedProcess.run("/bin/dd", ["if=/dev/zero", "bs=65536", "count=16"], limit: 1024) }
            rejects { _ = try BoundedProcess.run("/bin/sleep", ["2"], timeout: 0.05) }
        }
        h.test("Identity checks protect PID reuse, UID, self and protected processes") {
            let original = ProcessIdentity(pid: 555, uid: 501, startSeconds: 1, startMicroseconds: 2, name: "fixture")
            let recycled = ProcessIdentity(pid: 555, uid: 501, startSeconds: 3, startMicroseconds: 2, name: "fixture")
            var signals = 0
            let signal: (Int32) -> Bool = { _ in signals += 1; return true }
            assertFalse(TerminationPolicy.terminate(expected: original, ownPID: 10, uid: 501, lookup: { _ in recycled }, signal: signal))
            assertFalse(TerminationPolicy.terminate(expected: original, ownPID: 555, uid: 501, lookup: { _ in original }, signal: signal))
            assertFalse(TerminationPolicy.terminate(expected: original, ownPID: 10, uid: 999, lookup: { _ in original }, signal: signal))
            assertEqual(signals, 0)
            assertTrue(TerminationPolicy.terminate(expected: original, ownPID: 10, uid: 501, lookup: { _ in original }, signal: signal))
            assertEqual(signals, 1)
            assertFalse(TerminationPolicy.terminate(expected: original, ownPID: 10, uid: 501, lookup: { _ in original }, signal: { _ in false }))
            for pid: Int32 in [-1, 0, 1] {
                let item = ProcessIdentity(pid: pid, uid: 501, startSeconds: 1, startMicroseconds: 0, name: "fixture")
                assertFalse(TerminationPolicy.terminate(expected: item, ownPID: 10, uid: 501, lookup: { _ in item }, signal: signal))
            }
            let protected = ProcessIdentity(pid: 500, uid: 501, startSeconds: 1, startMicroseconds: 0, name: "loginwindow")
            assertFalse(TerminationPolicy.terminate(expected: protected, ownPID: 10, uid: 501, lookup: { _ in protected }, signal: signal))
        }
        h.test("Process snapshot parser rejects invalid and lossy numeric fields") {
            let valid = ProcessSnapshotParser.parse("42 12.5 1024 /Applications/Fixture App")
            assertEqual(valid, ProcessSample(pid: 42, cpuPercent: 12.5, residentKB: 1024, command: "/Applications/Fixture App"))
            for line in ["0 1 1 x", "-2 1 1 x", "999999999999999999999 1 1 x", "2 nan 1 x",
                         "2 inf 1 x", "2 -1 1 x", "2 1 -1 x", "2 1 inf x", "2 1 1"] {
                assertNil(ProcessSnapshotParser.parse(line))
            }
        }
    }
    h.runSuite("Security: models, web and transaction") {
        h.test("Tap lifecycle handles revocation, failed creation and repeated start/stop") {
            let state = TapLifecycle()
            var creations = 0, destructions = 0
            let create: () -> Bool = { creations += 1; return true }
            let destroy = { destructions += 1 }
            state.requested = true
            state.reconcile(permission: false, create: create, destroy: destroy)
            assertEqual(creations, 0); assertFalse(state.running)
            state.reconcile(permission: true, create: { false }, destroy: destroy)
            assertFalse(state.running)
            state.reconcile(permission: true, create: create, destroy: destroy)
            state.reconcile(permission: true, create: create, destroy: destroy)
            assertEqual(creations, 1); assertTrue(state.running)
            state.reconcile(permission: false, create: create, destroy: destroy)
            assertEqual(destructions, 1); assertFalse(state.running)
            state.requested = false
            state.reconcile(permission: true, create: create, destroy: destroy)
            assertEqual(creations, 1)
            assertTrue(ScrollReverserManager.shouldTransform(.scrollWheel))
            assertFalse(ScrollReverserManager.shouldTransform(.keyDown))
            assertFalse(ScrollReverserManager.shouldTransform(.leftMouseDown))
            assertEqual(ScrollReverserManager.eventMask, CGEventMask(1 << CGEventType.scrollWheel.rawValue))
        }
        h.test("Single-flight prevents overlapping work and resets after completion") {
            let gate = SingleFlight()
            assertTrue(gate.begin()); assertFalse(gate.begin()); gate.end(); assertTrue(gate.begin()); gate.end()
        }
        h.test("WebView uses isolated stores and forbids automatic popups") {
            let firstID = UUID(), secondID = UUID()
            var a: WebPanelController? = WebPanelController(initialURL: "https://example.invalid", widgetID: firstID, preload: false)
            var b: WebPanelController? = WebPanelController(initialURL: "https://example.invalid", widgetID: secondID, preload: false)
            assertFalse(a!.webView.configuration.websiteDataStore === b!.webView.configuration.websiteDataStore)
            assertFalse(a!.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
            assertFalse(a!.webView.configuration.preferences.isElementFullscreenEnabled)
            assertTrue(a!.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
            let firstCookie = HTTPCookie(properties: [.domain: "example.invalid", .path: "/", .name: "fixture-a", .value: "isolated", .secure: "TRUE"])!
            let secondCookie = HTTPCookie(properties: [.domain: "example.invalid", .path: "/", .name: "fixture-b", .value: "isolated", .secure: "TRUE"])!
            var writes = 0
            a!.webView.configuration.websiteDataStore.httpCookieStore.setCookie(firstCookie) { writes += 1 }
            b!.webView.configuration.websiteDataStore.httpCookieStore.setCookie(secondCookie) { writes += 1 }
            pump { writes == 2 }
            a!.dispose(); b!.dispose()
            a = nil; b = nil

            var removalFinished = false, removalError: Error?
            IsolatedWebsiteDataStore.remove(identifier: firstID) { removalError = $0; removalFinished = true }
            pump { removalFinished }
            // The process may still retain the now-empty container. That removal error must
            // be observable rather than converted to success (YEA-06).
            if let removalError = removalError as NSError? {
                assertEqual(removalError.domain, "WKWebSiteDataStore")
                assertEqual(removalError.code, 1)
            }
            var firstCookies: [HTTPCookie]?, secondCookies: [HTTPCookie]?
            WKWebsiteDataStore(forIdentifier: firstID).httpCookieStore.getAllCookies { firstCookies = $0 }
            WKWebsiteDataStore(forIdentifier: secondID).httpCookieStore.getAllCookies { secondCookies = $0 }
            pump { firstCookies != nil && secondCookies != nil }
            assertFalse(firstCookies!.contains { $0.name == "fixture-a" })
            assertTrue(secondCookies!.contains { $0.name == "fixture-b" })
            for id in [firstID, secondID] {
                var cleaned = false
                IsolatedWebsiteDataStore.remove(identifier: id) { _ in cleaned = true }
                pump { cleaned }
            }
        }
        h.test("Settings clamp extreme values and arithmetic rejects overflows") {
            assertEqual(SecurityPolicy.bounded(.nan, 0.5...1.5, fallback: 1), 1)
            assertEqual(SecurityPolicy.bounded(.infinity, 0.5...1.5, fallback: 1), 1)
            let item = WebWidgetItem(title: "fixture", url: "https://example.com", customWidth: -1, customHeight: 1e100, zoomScale: -4)
            assertEqual(item.customWidth, 280); assertEqual(item.customHeight, 1000); assertEqual(item.zoomScale, 0.5)
            assertNil(SecurityPolicy.multiply(Int64.min, by: -1))
            assertNil(SecurityPolicy.multiply(Int64.max, by: 5))
            assertEqual(SecurityPolicy.multiply(-2, by: -5), 10)
        }
        h.test("Widget validation rejects unsafe URLs, duplicate IDs and excessive counts") {
            for url in ["javascript:alert(1)", "file:///tmp/a", "data:text/plain,x", "https://u:p@example.com"] { assertNil(SecurityPolicy.webURL(url)) }
            let item = WebWidgetItem(title: "fixture", url: "https://example.com/?token=synthetic")
            rejects { _ = try WidgetStorage.decode(JSONEncoder().encode([item, item])) }
            rejects { _ = try WidgetStorage.decode(Data(repeating: 0, count: 1_048_577)) }
            assertEqual(SecurityPolicy.origin(URL(string: "https://example.com/login?q=secret")), "https://example.com")
        }
        h.test("Favicon keys are collision-resistant and profile-scoped") {
            let id = UUID(), raw = "https://example.com/" + String(repeating: "x", count: 200)
            assertFalse(WebFaviconManager.cacheKey(widget: id, url: raw + "a", removeWhite: false) == WebFaviconManager.cacheKey(widget: id, url: raw + "b", removeWhite: false))
            assertFalse(WebFaviconManager.cacheKey(widget: id, url: raw, removeWhite: false) == WebFaviconManager.cacheKey(widget: UUID(), url: raw, removeWhite: false))
            let page = URL(string: "https://example.com/app")!
            assertTrue(WebFaviconManager.allows(candidate: URL(string: "https://example.com/favicon.ico")!, page: page))
            assertFalse(WebFaviconManager.allows(candidate: URL(string: "https://cdn.example.com/favicon.ico")!, page: page))
            assertFalse(WebFaviconManager.allows(candidate: URL(string: "https://127.0.0.1/favicon.ico")!, page: page))
            assertFalse(WebFaviconManager.allows(candidate: URL(string: "http://example.com/favicon.ico")!, page: page))
        }
        h.test("Image decoder checks encoded and pixel limits before conversion") {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = rep.representation(using: .png, properties: [:])!
            assertEqual(try BoundedImage.decode(png).width, 10)
            rejects { _ = try BoundedImage.decode(png, bytes: 1) }
            rejects { _ = try BoundedImage.decode(png, pixels: 99) }
            rejects { _ = try BoundedImage.decode(Data("not an image".utf8)) }
        }
        h.test("Install transaction rolls back failed move and failed final verification") {
            try temporary { root in
                for failVerification in [false, true] {
                    let caseDir = try root.child(failVerification ? "verify" : "move")
                    try caseDir.write(Data("old".utf8), name: "target")
                    try caseDir.write(Data("new".utf8), name: "staged")
                    let target = caseDir.url.appendingPathComponent("target"), staged = caseDir.url.appendingPathComponent("staged"), backup = caseDir.url.appendingPathComponent("backup")
                    rejects {
                        try InstallTransaction.replace(staged: staged, target: target, backup: backup, verify: { url in
                            if failVerification && url == target { throw SecurityFailure.rejected("fixture verification failure") }
                        }, move: { from, to in
                            if !failVerification && from == staged { throw SecurityFailure.rejected("fixture disk full") }
                            try FileManager.default.moveItem(at: from, to: to)
                        })
                    }
                    assertEqual(try caseDir.read("target", limit: 10), Data("old".utf8))
                }
            }
        }
        h.test("Recovery restores a missing target and never overwrites a present target") {
            try temporary { root in
                try root.write(Data("old".utf8), name: "backup")
                let target = root.url.appendingPathComponent("target"), backup = root.url.appendingPathComponent("backup")
                try InstallTransaction.recover(target: target, backup: backup, verify: { _ in })
                assertEqual(try root.read("target", limit: 10), Data("old".utf8))
                try root.write(Data("other".utf8), name: "backup")
                rejects { try InstallTransaction.recover(target: target, backup: backup, verify: { _ in }) }
                assertEqual(try root.read("target", limit: 10), Data("old".utf8))
            }
        }
        h.test("Real ad-hoc signature accepts fixture and rejects modified executable") {
            try temporary { root in
                let app = try root.child("Yeoman.app"), contents = try app.child("Contents"), binaries = try contents.child("MacOS")
                let plist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": "1.2.3", "CFBundleExecutable": "Yeoman", "CFBundlePackageType": "APPL"]
                try contents.write(PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), name: "Info.plist")
                // Copy a benign system executable as a signing fixture; never execute it.
                try binaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/echo")), name: "Yeoman")
                let binary = binaries.url.appendingPathComponent("Yeoman")
                assertEqual(chmod(binary.path, 0o700), 0)
                let sign = try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", app.url.path], timeout: 10)
                assertEqual(sign.status, 0)
                try BundleVerifier.verify(app.url, version: "1.2.3")
                try binaries.write(Data("tampered".utf8), name: "Yeoman")
                rejects { try BundleVerifier.verify(app.url, version: "1.2.3") }
            }
        }
        h.test("BundleVerifier reads fresh Info.plist on version replacement (AUD-01)") {
            try temporary { root in
                let target = try root.child("target.app")
                let tContents = try target.child("Contents"), tBinaries = try tContents.child("MacOS")
                let tPlist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": "1.0.0", "CFBundleExecutable": "Yeoman", "CFBundlePackageType": "APPL"]
                try tContents.write(PropertyListSerialization.data(fromPropertyList: tPlist, format: .xml, options: 0), name: "Info.plist")
                try tBinaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/echo")), name: "Yeoman")
                assertEqual(chmod(tBinaries.url.appendingPathComponent("Yeoman").path, 0o700), 0)
                assertEqual(try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", target.url.path], timeout: 10).status, 0)
                try BundleVerifier.verify(target.url, version: "1.0.0")

                let staged = try root.child("staged.app")
                let sContents = try staged.child("Contents"), sBinaries = try sContents.child("MacOS")
                let sPlist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": "2.0.0", "CFBundleExecutable": "Yeoman", "CFBundlePackageType": "APPL"]
                try sContents.write(PropertyListSerialization.data(fromPropertyList: sPlist, format: .xml, options: 0), name: "Info.plist")
                try sBinaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/echo")), name: "Yeoman")
                assertEqual(chmod(sBinaries.url.appendingPathComponent("Yeoman").path, 0o700), 0)
                assertEqual(try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", staged.url.path], timeout: 10).status, 0)

                let backup = root.url.appendingPathComponent("backup.app")
                try InstallTransaction.replace(staged: staged.url, target: target.url, backup: backup) {
                    try BundleVerifier.verify($0, version: "2.0.0")
                }
                assertEqual(try BundleVerifier.readVersion(target.url), "2.0.0")
            }
        }
        h.test("InstallTransaction rejects substituted bundle with different code identity (AUD-04)") {
            try temporary { root in
                let staged = try root.child("staged.app")
                let sContents = try staged.child("Contents"), sBinaries = try sContents.child("MacOS")
                let sPlist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": "2.0.0", "CFBundleExecutable": "Yeoman", "CFBundlePackageType": "APPL"]
                try sContents.write(PropertyListSerialization.data(fromPropertyList: sPlist, format: .xml, options: 0), name: "Info.plist")
                try sBinaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/echo")), name: "Yeoman")
                assertEqual(chmod(sBinaries.url.appendingPathComponent("Yeoman").path, 0o700), 0)
                assertEqual(try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", staged.url.path], timeout: 10).status, 0)

                let target = try root.child("target.app")
                let tContents = try target.child("Contents"), tBinaries = try tContents.child("MacOS")
                let tPlist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": "1.0.0", "CFBundleExecutable": "Yeoman", "CFBundlePackageType": "APPL"]
                try tContents.write(PropertyListSerialization.data(fromPropertyList: tPlist, format: .xml, options: 0), name: "Info.plist")
                try tBinaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/echo")), name: "Yeoman")
                assertEqual(chmod(tBinaries.url.appendingPathComponent("Yeoman").path, 0o700), 0)
                assertEqual(try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", target.url.path], timeout: 10).status, 0)

                let evil = try root.child("evil.app")
                let eContents = try evil.child("Contents"), eBinaries = try eContents.child("MacOS")
                try eContents.write(PropertyListSerialization.data(fromPropertyList: sPlist, format: .xml, options: 0), name: "Info.plist")
                try eBinaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/cat")), name: "Yeoman")
                assertEqual(chmod(eBinaries.url.appendingPathComponent("Yeoman").path, 0o700), 0)
                assertEqual(try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", evil.url.path], timeout: 10).status, 0)

                let backup = root.url.appendingPathComponent("backup.app")
                rejects {
                    try InstallTransaction.replace(staged: staged.url, target: target.url, backup: backup, verify: {
                        try BundleVerifier.verify($0, version: "2.0.0")
                    }, move: { from, to in
                        if from == staged.url && to == target.url {
                            try FileManager.default.moveItem(at: evil.url, to: to)
                        } else {
                            try FileManager.default.moveItem(at: from, to: to)
                        }
                    })
                }
                assertEqual(try BundleVerifier.readVersion(target.url), "1.0.0")
            }
        }
        h.test("InstallTransaction binds signed resource changes into bundle identity") {
            try temporary { root in
                func makeApp(_ name: String, version: String, resource: String) throws -> SecureDirectory {
                    let app = try root.child(name)
                    let contents = try app.child("Contents")
                    let binaries = try contents.child("MacOS")
                    let resources = try contents.child("Resources")
                    let plist = ["CFBundleIdentifier": "de.trst.Yeoman", "CFBundleShortVersionString": version,
                                 "CFBundleExecutable": "Yeoman", "CFBundlePackageType": "APPL"]
                    try contents.write(PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), name: "Info.plist")
                    try binaries.write(Data(contentsOf: URL(fileURLWithPath: "/bin/echo")), name: "Yeoman")
                    assertEqual(chmod(binaries.url.appendingPathComponent("Yeoman").path, 0o700), 0)
                    try resources.write(Data(resource.utf8), name: "payload.txt")
                    assertEqual(try BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", app.url.path], timeout: 10).status, 0)
                    return app
                }

                let target = try makeApp("target.app", version: "1.0.0", resource: "old")
                let staged = try makeApp("staged.app", version: "2.0.0", resource: "authenticated")
                let substitute = try makeApp("substitute.app", version: "2.0.0", resource: "different")
                let stagedIdentity = try BundleVerifier.verify(staged.url, version: "2.0.0")
                let substituteIdentity = try BundleVerifier.verify(substitute.url, version: "2.0.0")
                // Re-signing embeds the resource envelope into the Mach-O signature, so both
                // the executable digest and the required code-directory identity may change.
                assertFalse(stagedIdentity.executableHash == substituteIdentity.executableHash)
                assertFalse(stagedIdentity.cdhash == substituteIdentity.cdhash)

                let backup = root.url.appendingPathComponent("backup.app")
                rejects {
                    try InstallTransaction.replace(staged: staged.url, target: target.url, backup: backup, verify: {
                        try BundleVerifier.verify($0, version: "2.0.0")
                    }, move: { from, to in
                        if from == staged.url && to == target.url {
                            try FileManager.default.moveItem(at: substitute.url, to: to)
                        } else {
                            try FileManager.default.moveItem(at: from, to: to)
                        }
                    })
                }
                assertEqual(try BundleVerifier.readVersion(target.url), "1.0.0")
            }
        }
        h.test("InstallTransaction rejects staging changed after authenticated identity capture") {
            try temporary { root in
                try root.write(Data("old".utf8), name: "target")
                try root.write(Data("authenticated".utf8), name: "staged")
                let target = root.url.appendingPathComponent("target")
                let staged = root.url.appendingPathComponent("staged")
                let backup = root.url.appendingPathComponent("backup")
                let expected = try root.read("staged", limit: 64)
                try root.write(Data("substitute".utf8), name: "staged")
                rejects {
                    try InstallTransaction.replace(staged: staged, target: target, backup: backup,
                                                   expectedIdentity: expected,
                                                   verify: { try Data(contentsOf: $0) })
                }
                assertEqual(try root.read("target", limit: 64), Data("old".utf8))
                assertFalse(try root.exists("backup"))
            }
        }
        h.test("Clipboard persistence opt-out is preserved with legacy directory (AUD-02)") {
            try temporary { root in
                let defaults = isolatedDefaults()
                defaults.set(false, forKey: "clipboard_encrypted_persistence")
                let legacyDir = try root.child("MacCustomizer")
                try legacyDir.write(Data("[]".utf8), name: "clipboard_history.json")
                let secrets = MemorySecrets()
                let store = ClipboardHistoryStore(directory: root.url.appendingPathComponent("Yeoman"), secrets: secrets, defaults: defaults)
                store.flushForTesting()
                assertFalse(store.isPersistent)
            }
        }
        h.test("Clipboard legacy migration merges new items into existing encrypted snapshot (AUD-03)") {
            try temporary { root in
                let defaults = isolatedDefaults()
                let secrets = MemorySecrets()
                let yeomanDir = try root.child("Yeoman")
                let item1 = ClipboardItem(content: "item 1", type: .text)
                var snapshot = ClipboardSnapshot()
                snapshot.items = [item1]
                let encDoc = try EncryptedDocument(directory: yeomanDir, name: "clipboard-v1.enc", secrets: secrets, limit: SecurityPolicy.historyBytes)
                try encDoc.write(JSONEncoder().encode(snapshot))

                let item2 = ClipboardItem(content: "item 2", type: .text)
                let legacyDir = try root.child("MacCustomizer")
                try legacyDir.write(JSONEncoder().encode([item2]), name: "clipboard_history.json")

                defaults.set(true, forKey: "clipboard_encrypted_persistence")
                let store = ClipboardHistoryStore(directory: yeomanDir.url, secrets: secrets, defaults: defaults)
                store.flushForTesting()
                pump { store.items.count == 2 }

                assertTrue(store.items.contains(where: { $0.content == "item 1" }))
                assertTrue(store.items.contains(where: { $0.content == "item 2" }))
                assertFalse(try legacyDir.exists("clipboard_history.json"))
            }
        }
        h.test("WidgetStorage repairs both WebKit UUID sentinels") {
            for raw in ["00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000001"] {
                let reserved = UUID(uuidString: raw)!
                assertFalse(reserved.isValidWebKitIdentifier)
                let item = WebWidgetItem(id: reserved, title: "Reserved", url: "https://example.com")
                let items = try WidgetStorage.decode(JSONEncoder().encode([item]))
                assertEqual(items.count, 1)
                assertTrue(items[0].id.isValidWebKitIdentifier)
                assertFalse(items[0].id == reserved)
            }
        }
        h.test("WidgetStorage persists repaired UUID across encrypted reloads (RR-01)") {
            try temporary { root in
                let appDirectory = try root.child("Yeoman")
                let defaults = isolatedDefaults()
                let secrets = MemorySecrets()
                let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                let item = WebWidgetItem(id: zero, title: "Zero", url: "https://example.com")
                let document = try EncryptedDocument(directory: appDirectory, name: "widgets-v1.enc", secrets: secrets, limit: 1_048_576)
                try document.write(JSONEncoder().encode([item]))

                var first: Result<[WebWidgetItem], Error>?
                WidgetStorage(url: appDirectory.url, defaults: defaults, secrets: secrets).load { first = $0 }
                pump { first != nil }
                let firstID = try first!.get().first!.id
                assertTrue(firstID.isValidWebKitIdentifier)

                var second: Result<[WebWidgetItem], Error>?
                WidgetStorage(url: appDirectory.url, defaults: defaults, secrets: secrets).load { second = $0 }
                pump { second != nil }
                assertEqual(try second!.get().first!.id, firstID)

                let persisted = try WidgetStorage.decode(try document.read()!)
                assertEqual(persisted.first!.id, firstID)
            }
        }
        h.test("WebPanelController dispose cancels delayed cache purge safely (AUD-06)") {
            let controller = WebPanelController(initialURL: "https://example.com", preload: false)
            controller.onPopoverClosed()
            controller.dispose()
            controller.purgeMemoryCache()
            RunLoop.current.run(until: Date().addingTimeInterval(3.2))
        }
        h.test("Image decoder accepts multi-frame ICO favicons (AUD-09)") {
            let data = NSMutableData()
            let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.tiff" as CFString, 2, nil)!
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let img = ctx.makeImage()!
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationAddImage(dest, img, nil)
            assertTrue(CGImageDestinationFinalize(dest))
            let decoded = try BoundedImage.decode(data as Data)
            assertEqual(decoded.width, 16)
        }
    }
}
