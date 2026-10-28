import Foundation
import YeomanCore

func runSystemStatsTests() {
    let harness = TestHarness.shared
    
    harness.runSuite("SystemStats Tests") {
        harness.test("StatsLayoutMode raw values and backward compatibility") {
            // Canonical raw values
            assertEqual(StatsLayoutMode(rawValue: "Vertikal gestapelt"), .vertical, "Legacy raw value must map to .vertical")
            assertEqual(StatsLayoutMode(rawValue: "Vertikal (Balken unten)"), .verticalBarBottom, "New raw value must map to .verticalBarBottom")
            assertEqual(StatsLayoutMode(rawValue: "Horizontal nebeneinander"), .horizontal, "Canonical raw value must map to .horizontal")
            
            // Alternative aliases / feedback names
            assertEqual(StatsLayoutMode(rawValue: "vertical"), .vertical)
            assertEqual(StatsLayoutMode(rawValue: "vertical_bar_right"), .vertical)
            assertEqual(StatsLayoutMode(rawValue: "Vertikal (Balken rechts)"), .vertical)
            assertEqual(StatsLayoutMode(rawValue: "vertical_bar_bottom"), .verticalBarBottom)
            assertEqual(StatsLayoutMode(rawValue: "Vertikal gestapelt 2"), .verticalBarBottom)
            assertEqual(StatsLayoutMode(rawValue: "stacked_bar_bottom"), .verticalBarBottom)
            assertEqual(StatsLayoutMode(rawValue: "horizontal"), .horizontal)
            
            // Unknown / malformed
            assertTrue(StatsLayoutMode(rawValue: "unknown_invalid_mode") == nil, "Invalid string must yield nil")
        }
        
        harness.test("StatsLayoutMode has valid localization in all supported languages") {
            let manager = LocalizationManager(defaults: isolatedDefaults())
            let supportedLanguages: [AppLanguage] = [.german, .english, .spanish, .french]
            
            let layoutKeys = [
                "system_stats.layout_vertical",
                "system_stats.layout_vertical_bar_bottom",
                "system_stats.layout_horizontal",
                "system_stats.graph_minibar"
            ]
            
            for key in layoutKeys {
                for lang in supportedLanguages {
                    let text = manager.localized(key, for: lang)
                    assertTrue(!text.isEmpty, "Translation for \(key) in \(lang.rawValue) must not be empty")
                    assertTrue(text != key, "Translation for \(key) in \(lang.rawValue) must not be key identifier")
                }
            }
        }
        
        harness.test("calculatedStatusItemWidth adapts correctly for all layout modes") {
            let module = ModuleManager.shared.systemStatsModule
            
            // Ensure all 3 metrics are active
            module.showCPU = true
            module.showRAM = true
            module.showGPU = true
            module.showLabels = true
            module.showPercentage = true
            module.showGraphs = true
            module.useSubtleBackground = false
            
            module.layoutMode = .vertical
            let verticalWidth = module.calculatedStatusItemWidth()
            assertTrue(verticalWidth > 0, "Vertical width must be positive")
            
            module.layoutMode = .verticalBarBottom
            let barBottomWidth = module.calculatedStatusItemWidth()
            assertTrue(barBottomWidth > 0, "VerticalBarBottom width must be positive")
            // In verticalBarBottom, label and percentage are side-by-side with a wide bar underneath,
            // so each item is wider than vertical stacked (where text is stacked and bar is thin 4.5pt),
            // but more compact than horizontal (where text, percentage, and bar are all in a single line).
            assertTrue(barBottomWidth > verticalWidth, "BarBottom width should accommodate side-by-side text and bar")
            
            module.layoutMode = .horizontal
            let horizontalWidth = module.calculatedStatusItemWidth()
            assertTrue(horizontalWidth > barBottomWidth, "Horizontal width (everything side-by-side) should be widest")
            
            // Subtle background adds padding
            module.layoutMode = .verticalBarBottom
            module.useSubtleBackground = false
            let noBgWidth = module.calculatedStatusItemWidth()
            module.useSubtleBackground = true
            let withBgWidth = module.calculatedStatusItemWidth()
            assertTrue(withBgWidth > noBgWidth, "Subtle background must add padding")
            
            // Toggling metrics reduces width proportionally
            module.showGPU = false
            let twoMetricsWidth = module.calculatedStatusItemWidth()
            assertTrue(twoMetricsWidth < withBgWidth, "Disabling GPU must decrease width")
            
            // Fallback icon when all metrics disabled
            module.showCPU = false
            module.showRAM = false
            module.showGPU = false
            let fallbackWidth = module.calculatedStatusItemWidth()
            assertTrue(fallbackWidth > 0 && fallbackWidth <= 46.0, "Fallback width should be bounded")
            
            // Restore defaults
            module.showCPU = true
            module.showRAM = true
            module.showGPU = true
            module.useSubtleBackground = false
            module.layoutMode = .vertical
        }
    }
}
