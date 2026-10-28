import SwiftUI

public struct ScrollReverserSettingsView: View {
    @ObservedObject var module: ScrollReverserModule
    @ObservedObject var manager = ScrollReverserManager.shared
    @ObservedObject var l10nObj = LocalizationManager.shared
    
    public init(module: ScrollReverserModule) {
        self.module = module
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            ModuleHeaderView(
                title: l10n("scroll_reverser.title"),
                subtitle: l10n("scroll_reverser.subtitle"),
                icon: "computermouse",
                isEnabled: $module.isEnabled
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = manager.permissionError {
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                    Group {
                    // Accessibility Permission Banner (if missing)
                    if !manager.hasAccessibilityPermission {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(l10n("scroll_reverser.permission_required"))
                                        .fontWeight(.medium)
                                    Text(l10n("scroll_reverser.permission_description"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button(l10n("scroll_reverser.check_again")) {
                                        manager.checkAccessibility(prompt: false)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Button(l10n("scroll_reverser.open_settings")) {
                                        manager.openAccessibilitySettings()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            
                            Divider()
                            
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(l10n("scroll_reverser.permission_hint"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    // Card 1: Mouse Settings
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 6) {
                            Image(systemName: "computermouse")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                            Text(l10n("scroll_reverser.mouse_header"))
                                .font(.headline)
                            InfoTooltip(text: l10n("scroll_reverser.mouse_tooltip"))
                        }
                        
                        Divider()
                        
                        HStack(spacing: 6) {
                            Toggle(l10n("scroll_reverser.reverse_vertical"), isOn: $manager.reverseMouseVertical)
                                .font(.subheadline)
                            InfoTooltip(text: l10n("scroll_reverser.mouse_vertical_tooltip"))
                        }
                        
                        Toggle(l10n("scroll_reverser.reverse_horizontal"), isOn: $manager.reverseMouseHorizontal)
                            .font(.subheadline)
                        
                        HStack(spacing: 6) {
                            Text(l10n("scroll_reverser.step_multiplier"))
                                .font(.subheadline)
                            InfoTooltip(text: l10n("scroll_reverser.step_multiplier_tooltip"))
                            Spacer()
                            Picker("", selection: $manager.mouseStepMultiplier) {
                                Text(l10n("scroll_reverser.step_standard")).tag(1)
                                Text(l10n("scroll_reverser.step_faster")).tag(2)
                                Text("3x").tag(3)
                                Text("4x").tag(4)
                                Text(l10n("scroll_reverser.step_max")).tag(5)
                            }
                            .frame(width: 150)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    
                    // Card 2: Trackpad Settings
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                            Text(l10n("scroll_reverser.trackpad_header"))
                                .font(.headline)
                            InfoTooltip(text: l10n("scroll_reverser.trackpad_tooltip"))
                        }
                        
                        Divider()
                        
                        HStack(spacing: 6) {
                            Toggle(l10n("scroll_reverser.reverse_vertical"), isOn: $manager.reverseTrackpadVertical)
                                .font(.subheadline)
                            InfoTooltip(text: l10n("scroll_reverser.trackpad_vertical_tooltip"))
                        }
                        
                        Toggle(l10n("scroll_reverser.reverse_horizontal"), isOn: $manager.reverseTrackpadHorizontal)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    
                    // Card 3: Menu Bar Integration
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n("scroll_reverser.menubar_integration"))
                            .font(.headline)
                        
                        HStack(spacing: 6) {
                            Toggle(l10n("scroll_reverser.menubar_toggle"), isOn: $module.showsDedicatedStatusItem)
                                .font(.subheadline)
                            InfoTooltip(text: l10n("scroll_reverser.menubar_tooltip"))
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    
                    // Card 4: Status
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(manager.isRunning ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(l10n("scroll_reverser.status"))
                                .font(.headline)
                            Spacer()
                            Text(manager.isRunning ? l10n("scroll_reverser.status_active") : l10n("scroll_reverser.status_paused"))
                                .font(.caption)
                                .foregroundColor(manager.isRunning ? .green : .secondary)
                        }
                        
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .disabled(!module.isEnabled)
                .opacity(module.isEnabled ? 1.0 : 0.6)
            }
            .padding(20)
        }
    }
        .onAppear {
            manager.checkAccessibility(prompt: false)
            if !manager.hasAccessibilityPermission {
                manager.startPermissionPolling()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.checkAccessibility(prompt: false)
        }
        .onDisappear {
            if !manager.isRunning {
                manager.stopPermissionPolling()
            }
        }
    }
}
