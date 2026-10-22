import SwiftUI

public enum MenuBarSubTab: String, CaseIterable, Identifiable, SubTabProtocol {
    case items = "items"
    case spacing = "spacing"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .items: return l10n("menubar.tab_items")
        case .spacing: return l10n("menubar.tab_spacing")
        }
    }
    
    public var iconName: String {
        switch self {
        case .items: return "list.bullet.rectangle"
        case .spacing: return "arrow.left.and.line.vertical.and.arrow.right"
        }
    }
}

public struct MenuBarSettingsView: View {
    @ObservedObject var module: MenuBarModule
    @ObservedObject var l10nObj = LocalizationManager.shared
    
    public init(module: MenuBarModule) {
        self.module = module
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Module Header & Sub-Navigation
            VStack(spacing: 14) {
                ModuleHeaderView(
                    title: l10n("menubar.title"),
                    subtitle: l10n("menubar.subtitle"),
                    icon: "menubar.rectangle",
                    isEnabled: $module.isEnabled
                )
                
                // Unified sub-menu switcher for this module
                UnifiedSubTabBar(
                    tabs: MenuBarSubTab.allCases,
                    selectedTab: $module.activeSubTab
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Sub-Menu Content
            Group {
                switch module.activeSubTab {
                case .items:
                    MenuBarItemsView()
                case .spacing:
                    MenuBarSpacingSectionView(module: module)
                }
            }
            .disabled(!module.isEnabled)
            .opacity(module.isEnabled ? 1.0 : 0.6)
        }
    }
}

public struct MenuBarSpacingSectionView: View {
    @ObservedObject var module: MenuBarModule
    @ObservedObject var spacingManager = MenuBarSpacingManager.shared
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = spacingManager.lastError {
                    Text(error).font(.caption).foregroundColor(.red)
                }
                // Dedicated status item toggle
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Integration")
                        .font(.headline)
                    
                    HStack(spacing: 6) {
                        Toggle("Eigenes Symbol in der Menüleiste anzeigen", isOn: $module.showsDedicatedStatusItem)
                            .font(.subheadline)
                        InfoTooltip(text: "Ermöglicht das schnelle Wechseln der Abstands-Presets direkt über ein Menüleisten-Symbol.")
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Spacing Presets
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Abstand-Presets")
                            .font(.headline)
                        Spacer()
                        if spacingManager.isApplying {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Wird angewendet...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        PresetButton(title: "Ultra-Kompakt", subtitle: "4 pt", isSelected: spacingManager.currentSpacing == 4) {
                            spacingManager.applyPreset(.ultraCompact)
                        }
                        
                        PresetButton(title: "Kompakt", subtitle: "8 pt", isSelected: spacingManager.currentSpacing == 8) {
                            spacingManager.applyPreset(.compact)
                        }
                        
                        PresetButton(title: "Standard", subtitle: "16 pt", isSelected: spacingManager.currentSpacing == 16) {
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
                            Text("Abstand zwischen Symbolen:")
                            Spacer()
                            Text("\(spacingManager.currentSpacing) pt")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Binding(
                            get: { Double(spacingManager.currentSpacing) },
                            set: { spacingManager.setSpacingDebounced(spacing: Int($0), selectionPadding: spacingManager.currentSelectionPadding) }
                        ), in: 0...24, step: 1)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Klickbereich um Symbole:")
                            Spacer()
                            Text("\(spacingManager.currentSelectionPadding) pt")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Binding(
                            get: { Double(spacingManager.currentSelectionPadding) },
                            set: { spacingManager.setSpacingDebounced(spacing: spacingManager.currentSpacing, selectionPadding: Int($0)) }
                        ), in: 0...24, step: 1)
                    }
                    
                    Divider()
                    
                    HStack(spacing: 6) {
                        Toggle("Änderungen automatisch anwenden", isOn: Binding(
                            get: { spacingManager.autoRestartControlCenter },
                            set: { spacingManager.setAutoRestart($0) }
                        ))
                        .font(.subheadline)
                        InfoTooltip(text: "Startet das macOS ControlCenter bei Abstandsänderungen automatisch im Hintergrund neu.")
                    }
                    
                    HStack {
                        Button("Menüleiste jetzt aktualisieren") {
                            spacingManager.restartControlCenter()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Auf Standard zurücksetzen") {
                            spacingManager.resetToDefaults()
                        }
                        .buttonStyle(.bordered)
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
