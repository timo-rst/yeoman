import Foundation
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
    }
}
