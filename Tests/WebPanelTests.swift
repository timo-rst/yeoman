import Foundation
import WebKit
import YeomanCore

func runWebPanelTests() {
    let harness = TestHarness.shared

    harness.runSuite("WebPanel Tests") {
        harness.test("WebWidgetItem JSON serialization roundtrip") {
            let originalItem = WebWidgetItem(
                title: "GitHub Dashboard",
                url: "https://github.com/dashboard",
                iconName: "globe",
                useFavicon: true,
                selectedFaviconURL: "https://github.com/favicon.ico",
                removeWhiteBackground: true,
                sizePreset: .custom,
                customWidth: 320,
                customHeight: 400,
                userAgentMode: .mobile,
                zoomScale: 1.0,
                isEnabled: true,
                isPinned: true,
                showsAddressBar: false,
                showsTopBar: false
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(originalItem)
            assertTrue(data.count > 0, "Encoded JSON data should not be empty")

            let decoder = JSONDecoder()
            let decodedItem = try decoder.decode(WebWidgetItem.self, from: data)

            assertEqual(decodedItem.id, originalItem.id)
            assertEqual(decodedItem.title, originalItem.title)
            assertEqual(decodedItem.url, originalItem.url)
            assertEqual(decodedItem.iconName, originalItem.iconName)
            assertEqual(decodedItem.useFavicon, originalItem.useFavicon)
            assertEqual(decodedItem.selectedFaviconURL, originalItem.selectedFaviconURL)
            assertEqual(decodedItem.removeWhiteBackground, originalItem.removeWhiteBackground)
            assertEqual(decodedItem.sizePreset, originalItem.sizePreset)
            assertEqual(decodedItem.customWidth, originalItem.customWidth)
            assertEqual(decodedItem.customHeight, originalItem.customHeight)
            assertEqual(decodedItem.userAgentMode, originalItem.userAgentMode)
            assertEqual(decodedItem.isEnabled, originalItem.isEnabled)
            assertEqual(decodedItem.isPinned, originalItem.isPinned)
            assertEqual(decodedItem.showsAddressBar, originalItem.showsAddressBar)
            assertEqual(decodedItem.showsTopBar, originalItem.showsTopBar)
            assertEqual(decodedItem.hidesTopBar, originalItem.hidesTopBar)
        }

        harness.test("WebWidgetItem decodes legacy JSON without showsTopBar to true") {
            let legacyJSON = """
            {
                "id": "12345678-1234-1234-1234-123456789abc",
                "title": "Legacy Item",
                "url": "https://example.com",
                "iconName": "globe",
                "useFavicon": false,
                "removeWhiteBackground": false,
                "sizePreset": "320 × 400 (Widget)",
                "customWidth": 320,
                "customHeight": 400,
                "userAgentMode": "Immer Desktop",
                "zoomScale": 1.0,
                "isEnabled": true,
                "isPinned": false,
                "showsAddressBar": false
            }
            """.data(using: .utf8)!

            let decoded = try JSONDecoder().decode(WebWidgetItem.self, from: legacyJSON)
            assertTrue(decoded.showsTopBar, "Legacy widget without showsTopBar should default to true")
            assertFalse(decoded.hidesTopBar, "hidesTopBar should be false when showsTopBar is true")
        }

        harness.test("WebWidgetItem decodes JSON with legacy hidesTopBar flag") {
            let json = """
            {
                "id": "12345678-1234-1234-1234-123456789abc",
                "title": "Legacy Item",
                "url": "https://example.com",
                "sizePreset": "320 × 400 (Widget)",
                "userAgentMode": "Immer Desktop",
                "hidesTopBar": true
            }
            """.data(using: .utf8)!

            let decoded = try JSONDecoder().decode(WebWidgetItem.self, from: json)
            assertFalse(decoded.showsTopBar, "hidesTopBar=true should set showsTopBar=false")
            assertTrue(decoded.hidesTopBar)
        }

        harness.test("WebSizePreset dimensions are accurate") {
            assertEqual(WebSizePreset.custom.dimensions.width, 320)
            assertEqual(WebSizePreset.custom.dimensions.height, 400)

            assertEqual(WebSizePreset.widget.dimensions.width, 320)
            assertEqual(WebSizePreset.widget.dimensions.height, 400)

            assertEqual(WebSizePreset.smartphone.dimensions.width, 375)
            assertEqual(WebSizePreset.smartphone.dimensions.height, 667)

            assertEqual(WebSizePreset.large.dimensions.width, 500)
            assertEqual(WebSizePreset.large.dimensions.height, 700)
        }

        harness.test("WebPanelController presentation reload and navigation error policy") {
            assertTrue(WebPanelController.shouldLoadOnPresentation(
                hasPreloaded: false,
                hasCompletedLoad: false,
                needsReload: false,
                isLoading: false,
                hasCommittedURL: false
            ))
            assertTrue(WebPanelController.shouldLoadOnPresentation(
                hasPreloaded: true,
                hasCompletedLoad: false,
                needsReload: true,
                isLoading: false,
                hasCommittedURL: false
            ))
            assertFalse(WebPanelController.shouldLoadOnPresentation(
                hasPreloaded: true,
                hasCompletedLoad: false,
                needsReload: false,
                isLoading: true,
                hasCommittedURL: false
            ))
            assertFalse(WebPanelController.shouldLoadOnPresentation(
                hasPreloaded: true,
                hasCompletedLoad: true,
                needsReload: false,
                isLoading: false,
                hasCommittedURL: true
            ))
            assertTrue(WebPanelController.shouldLoadOnPresentation(
                hasPreloaded: true,
                hasCompletedLoad: true,
                needsReload: false,
                isLoading: false,
                hasCommittedURL: false
            ))

            let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            assertTrue(WebPanelController.shouldIgnoreNavigationError(cancelled))

            let webkitFrameInterrupted = NSError(domain: "WebKitErrorDomain", code: 102)
            assertTrue(WebPanelController.shouldIgnoreNavigationError(webkitFrameInterrupted))

            let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            assertFalse(WebPanelController.shouldIgnoreNavigationError(offline))

            assertEqual(WebPanelController.retryDelay(forAttempt: 0), 2.0)
            assertEqual(WebPanelController.retryDelay(forAttempt: 1), 5.0)
            assertEqual(WebPanelController.retryDelay(forAttempt: 2), 10.0)
            assertTrue(WebPanelController.retryDelay(forAttempt: 3) == nil)
        }

        harness.test("WebPanelController recovers from provisional failure, process termination, and network availability") {
            let controller = WebPanelController(initialURL: "https://example.invalid", preload: false)
            defer { controller.dispose() }

            // Simulate provisional boot failure (e.g. Launch at Login before Wi-Fi connects)
            let offlineError = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
            )
            controller.webView(controller.webView, didFailProvisionalNavigation: nil, withError: offlineError)
            assertTrue(controller.needsReload, "Provisional failure must mark needsReload = true")
            assertFalse(controller.hasCompletedLoad)
            assertFalse(controller.isLoading)
            assertTrue(controller.lastLoadError != nil)

            // reload() when webView.url == nil must start a fresh load instead of no-op WKWebView.reload()
            controller.reload()
            assertFalse(controller.needsReload, "reload() should clear needsReload and start fresh load")
            assertTrue(controller.isLoading, "reload() should transition to isLoading = true")
            assertTrue(controller.lastLoadError == nil)

            // Simulate another failure and verify handleNetworkBecameAvailable() initiates recovery
            controller.webView(controller.webView, didFailProvisionalNavigation: nil, withError: offlineError)
            assertTrue(controller.needsReload)
            controller.handleNetworkBecameAvailable()
            assertFalse(controller.needsReload, "Network recovery must initiate a fresh load")
            assertTrue(controller.isLoading)

            // Simulate WebContent process termination
            controller.webViewWebContentProcessDidTerminate(controller.webView)
            assertTrue(controller.needsReload, "Process termination must mark needsReload = true")
            assertFalse(controller.hasCompletedLoad)
            assertFalse(controller.isLoading)

            // Presentation on popover open should trigger load when needsReload is set
            controller.onPopoverOpened()
            assertFalse(controller.needsReload, "Opening popover when needsReload is true must trigger load")
            assertTrue(controller.isLoading)
        }

        harness.test("WebPanelController dispose safely cancels pending retry timers") {
            let controller = WebPanelController(initialURL: "https://example.invalid", preload: false)
            let offlineError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            controller.webView(controller.webView, didFailProvisionalNavigation: nil, withError: offlineError)
            assertTrue(controller.needsReload)

            controller.dispose()
            assertFalse(controller.needsReload)
            assertFalse(controller.isLoading)

            // Ensure calling recovery/reload after dispose is a safe no-op
            controller.handleNetworkBecameAvailable()
            controller.handleSystemWake()
            controller.reload()
            controller.onPopoverOpened()
        }
    }
}
