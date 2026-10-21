import SwiftUI

public enum MenuBarSubTab: String, CaseIterable, Identifiable {
    case items = "Icons & Sichtbarkeit"
    case appearance = "Design & Hintergrund"
    case spacing = "Abstände (Ice)"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .items: return "list.bullet.rectangle"
        case .appearance: return "paintpalette"
        case .spacing: return "arrow.left.and.line.vertical.and.arrow.right"
        }
    }
}

public struct MenuBarSettingsView: View {
    @ObservedObject var module: MenuBarModule
    @State private var selectedSubTab: MenuBarSubTab = .items
    
    public init(module: MenuBarModule) {
        self.module = module
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Module Header & Sub-Navigation Picker
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menüleisten-Optimizer (Ice-Modul)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Verwalte Icons, visuelles Design, Transparenz und Menüleisten-Abstände.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Modul aktiv", isOn: $module.isEnabled)
                        .toggleStyle(.switch)
                }
                
                // Sub-menu switcher for this module
                Picker("", selection: $selectedSubTab) {
                    ForEach(MenuBarSubTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Sub-Menu Content
            Group {
                switch selectedSubTab {
                case .items:
                    MenuBarItemsView()
                case .appearance:
                    MenuBarAppearanceView()
                case .spacing:
                    MenuBarSpacingSectionView(module: module)
                }
            }
        }
    }
}

public struct MenuBarSpacingSectionView: View {
    @ObservedObject var module: MenuBarModule
    @ObservedObject var spacingManager = MenuBarSpacingManager.shared
    @ObservedObject var displayManager = DisplayManager.shared
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Dedicated status item toggle
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Integration")
                        .font(.headline)
                    
                    Toggle("Eigenes Icon in der Menüleiste anzeigen (Schnell-Umschalter für Abstände)", isOn: $module.showsDedicatedStatusItem)
                        .font(.subheadline)
                    
                    Text("Zeigt ein separates Symbol in der Menüleiste an, über das du die Abstands-Presets per Klick wechseln kannst.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Spacing Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Abstand-Presets")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        PresetButton(title: "Ultra-Kompakt", subtitle: "4 pt", isSelected: spacingManager.currentSpacing == 4) {
                            spacingManager.applyPreset(.ultraCompact)
                        }
                        
                        PresetButton(title: "Kompakt (Ice)", subtitle: "8 pt", isSelected: spacingManager.currentSpacing == 8) {
                            spacingManager.applyPreset(.compact)
                        }
                        
                        PresetButton(title: "Standard", subtitle: "16 pt (macOS)", isSelected: spacingManager.currentSpacing == 16) {
                            spacingManager.applyPreset(.standard)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Manual Fine-Tuning Slider
                VStack(alignment: .leading, spacing: 14) {
                    Text("Feinabstimmung (Pixel-genau)")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Symbol-Abstand (Spacing):")
                            Spacer()
                            Text("\(spacingManager.currentSpacing) pt")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Binding(
                            get: { Double(spacingManager.currentSpacing) },
                            set: { spacingManager.applySpacing(spacing: Int($0), selectionPadding: spacingManager.currentSelectionPadding) }
                        ), in: 0...24, step: 1)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Auswahl-Padding (Selection Padding):")
                            Spacer()
                            Text("\(spacingManager.currentSelectionPadding) pt")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Binding(
                            get: { Double(spacingManager.currentSelectionPadding) },
                            set: { spacingManager.applySpacing(spacing: spacingManager.currentSpacing, selectionPadding: Int($0)) }
                        ), in: 0...24, step: 1)
                    }
                    
                    HStack {
                        Button("ControlCenter neu laden") {
                            spacingManager.restartControlCenter()
                        }
                        
                        Spacer()
                        
                        Button("Auf macOS Standard zurücksetzen") {
                            spacingManager.resetToDefaults()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Multi-Display Status & Detection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "display.2")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                        Text("Multi-Monitor Status")
                            .font(.headline)
                        Spacer()
                        Text("\(displayManager.displays.count) Bildschirm(e) erkannt")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(displayManager.displays) { display in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(display.name)
                                        .fontWeight(.medium)
                                    if display.isMain {
                                        Text("Hauptbildschirm")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                            .foregroundColor(.accentColor)
                                    }
                                    if display.hasNotch {
                                        Text("Notch")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                                            .foregroundColor(.orange)
                                    }
                                }
                                Text("\(Int(display.frame.width)) x \(Int(display.frame.height)) @ \(Int(display.backingScaleFactor))x (Menüleiste: \(Int(display.menuBarHeight))pt)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
}

struct PresetButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
