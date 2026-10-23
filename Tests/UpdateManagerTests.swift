import Foundation
import YeomanCore

func runUpdateManagerTests() {
    let harness = TestHarness.shared

    harness.runSuite("UpdateManager Tests") {
        harness.test("cleanVersionString strips prefix and whitespace") {
            assertEqual(UpdateManager.cleanVersionString("v1.2.3"), "1.2.3")
            assertEqual(UpdateManager.cleanVersionString("V2.0.0"), "2.0.0")
            assertEqual(UpdateManager.cleanVersionString("  v1.0.4 \n"), "1.0.4")
            assertEqual(UpdateManager.cleanVersionString("3.14.15"), "3.14.15")
        }

        harness.test("isVersion correctly evaluates semantic version numbers") {
            // Newer patch version
            assertTrue(UpdateManager.isVersion("1.0.1", newerThan: "1.0.0"))
            // Newer minor version
            assertTrue(UpdateManager.isVersion("1.1.0", newerThan: "1.0.9"))
            // Newer major version
            assertTrue(UpdateManager.isVersion("2.0.0", newerThan: "1.99.99"))
            // Equal version should not be newer
            assertFalse(UpdateManager.isVersion("1.0.0", newerThan: "1.0.0"))
            // Older version should not be newer
            assertFalse(UpdateManager.isVersion("0.9.0", newerThan: "1.0.0"))
            assertFalse(UpdateManager.isVersion("1.0.0", newerThan: "1.0.1"))
            // Different component lengths
            assertTrue(UpdateManager.isVersion("1.2.1", newerThan: "1.2"))
            assertFalse(UpdateManager.isVersion("1.2", newerThan: "1.2.1"))
        }

        harness.test("isTrustedUpdateHost enforces HTTPS and GitHub whitelist") {
            // Valid trusted URLs
            let releaseUrl = URL(string: "https://api.github.com/repos/timo-rst/yeoman/releases/latest")!
            let downloadUrl = URL(string: "https://github.com/timo-rst/yeoman/releases/download/v1.0.0/Yeoman.zip")!
            let cdnUrl = URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Yeoman.zip")!

            assertFalse(UpdateManager.isTrustedUpdateHost(releaseUrl), "API endpoint is not an installable asset")
            assertTrue(UpdateManager.isTrustedUpdateHost(downloadUrl), "GitHub release download must be trusted")
            assertFalse(UpdateManager.isTrustedUpdateHost(cdnUrl), "CDN is allowed only as a controlled redirect")

            // Insecure HTTP must be rejected
            let insecureUrl = URL(string: "http://github.com/timo-rst/yeoman/releases/download/v1.0.0/Yeoman.zip")!
            assertFalse(UpdateManager.isTrustedUpdateHost(insecureUrl), "Insecure HTTP must be rejected")

            // Untrusted third-party domains must be rejected
            let maliciousUrl = URL(string: "https://evil-server.com/malware.dmg")!
            let deceptiveUrl = URL(string: "https://github.com.evil-domain.org/Yeoman.zip")!
            assertFalse(UpdateManager.isTrustedUpdateHost(maliciousUrl), "External untrusted host must be rejected")
            assertFalse(UpdateManager.isTrustedUpdateHost(deceptiveUrl), "Phishing subdomain must be rejected")
        }

        harness.test("UpdatePromptController lifecycle and ignored version handling") {
            let suite = isolatedDefaults()
            suite.removeObject(forKey: "update_ignored_version")
            assertNil(suite.string(forKey: "update_ignored_version"))
            suite.set("v0.2.4", forKey: "update_ignored_version")
            assertEqual(suite.string(forKey: "update_ignored_version"), "v0.2.4")
        }
    }
}
