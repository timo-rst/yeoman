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
                sizePreset: .iphone14,
                customWidth: 390,
                customHeight: 844,
                userAgentMode: .mobile,
                zoomScale: 1.0,
                isEnabled: true,
                isPinned: true,
                showsAddressBar: false
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
        }
        
        harness.test("WebSizePreset dimensions are accurate") {
            assertEqual(WebSizePreset.widget.dimensions.width, 320)
            assertEqual(WebSizePreset.widget.dimensions.height, 400)
            
            assertEqual(WebSizePreset.iphone14.dimensions.width, 390)
            assertEqual(WebSizePreset.iphone14.dimensions.height, 844)
            
            assertEqual(WebSizePreset.ipadMini.dimensions.width, 768)
            assertEqual(WebSizePreset.ipadMini.dimensions.height, 1024)
        }
    }
}
