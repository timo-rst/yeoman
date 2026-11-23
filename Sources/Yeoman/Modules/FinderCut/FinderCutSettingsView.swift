import SwiftUI
import AppKit

public struct FinderCutSettingsView: View {
    @ObservedObject var module: FinderCutModule
    @ObservedObject var manager = FinderCutManager.shared
    @ObservedObject var l10nObj = LocalizationManager.shared

    public init(module: FinderCutModule) {
        self.module = module
    }

    public var body: some View {
        VStack(spacing: 0) {
            ModuleHeaderView(
                title: l10n("finder_cut.title"),
                subtitle: l10n("finder_cut.subtitle"),
                icon: "scissors",
                isEnabled: $module.isEnabled
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        if !manager.hasAccessibilityPermission {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 14) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(l10n("finder_cut.permission_required"))
                                            .fontWeight(.medium)
                                        Text(l10n("finder_cut.permission_description"))
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

                        // Card 1: Shortcut Overview
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 6) {
                                Image(systemName: "keyboard")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                Text(l10n("finder_cut.how_it_works"))
                                    .font(.headline)
                            }

                            Divider()

                            ShortcutRow(keys: "⌘X", description: l10n("finder_cut.shortcut_cut"))
                            ShortcutRow(keys: "⌘V", description: l10n("finder_cut.shortcut_paste"))
                            ShortcutRow(keys: "⌘C / Esc", description: l10n("finder_cut.shortcut_cancel"))

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text(l10n("finder_cut.text_safe_note"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                        // Card 2: Options
                        VStack(alignment: .leading, spacing: 14) {
                            Text(l10n("finder_cut.options_header"))
                                .font(.headline)

                            Divider()

                            HStack(spacing: 6) {
                                Toggle(l10n("finder_cut.play_sound"), isOn: $manager.playFeedbackSound)
                                    .font(.subheadline)
                                InfoTooltip(text: l10n("finder_cut.play_sound_tooltip"))
                            }

                            HStack(spacing: 6) {
                                Toggle(l10n("finder_cut.cancel_on_escape"), isOn: $manager.cancelOnEscape)
                                    .font(.subheadline)
                                InfoTooltip(text: l10n("finder_cut.cancel_on_escape_tooltip"))
                            }

                            HStack(spacing: 6) {
                                Toggle(l10n("finder_cut.show_hud"), isOn: $manager.showVisualHUD)
                                    .font(.subheadline)
                                InfoTooltip(text: l10n("finder_cut.show_hud_tooltip"))
                            }

                            HStack(spacing: 6) {
                                Toggle(l10n("finder_cut.menubar_toggle"), isOn: $module.showsDedicatedStatusItem)
                                    .font(.subheadline)
                                InfoTooltip(text: l10n("finder_cut.menubar_tooltip"))
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

private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 84)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

public struct FinderCutPermissionPromptView: View {
    @ObservedObject var manager: FinderCutManager
    @ObservedObject private var l10nObj = LocalizationManager.shared
    let onOpenSettings: () -> Void
    let onDismissLater: () -> Void
    let onDisableModule: () -> Void

    public init(
        manager: FinderCutManager,
        onOpenSettings: @escaping () -> Void,
        onDismissLater: @escaping () -> Void,
        onDisableModule: @escaping () -> Void
    ) {
        self.manager = manager
        self.onOpenSettings = onOpenSettings
        self.onDismissLater = onDismissLater
        self.onDisableModule = onDisableModule
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "scissors")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: 52, height: 52)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1))
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n("finder_cut.prompt_title"))
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(l10n("finder_cut.prompt_message"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(l10n("finder_cut.prompt_steps"))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(l10n("scroll_reverser.permission_hint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 10) {
                Button(l10n("finder_cut.prompt_disable")) {
                    onDisableModule()
                }
                .buttonStyle(.bordered)
                .focusable(false)
                .focusEffectDisabled()

                Spacer()

                Button(l10n("finder_cut.prompt_later")) {
                    onDismissLater()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .focusable(false)
                .focusEffectDisabled()

                Button(l10n("scroll_reverser.open_settings")) {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
    }
}

public final class FinderCutPermissionPromptController: NSObject, NSWindowDelegate {
    public static let shared = FinderCutPermissionPromptController()

    private var promptWindow: NSWindow?
    private weak var manager: FinderCutManager?
    private var suppressDismissNotification = false

    private override init() {
        super.init()
    }

    public func show(manager: FinderCutManager) {
        precondition(Thread.isMainThread)
        self.manager = manager
        if let window = promptWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        let view = FinderCutPermissionPromptView(
            manager: manager,
            onOpenSettings: {
                manager.openAccessibilitySettings()
            },
            onDismissLater: { [weak self] in
                self?.dismissFromUser(muteForSession: false)
            },
            onDisableModule: { [weak self] in
                self?.dismissFromUser(muteForSession: true)
                ModuleManager.shared.toggleModule(id: "finder_cut", enabled: false)
            }
        )

        let hostingController = NSHostingController(rootView: view)
        let fittingSize = hostingController.view.fittingSize
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: max(480, fittingSize.width),
                height: max(250, fittingSize.height)
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n("finder_cut.prompt_window_title")
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        self.promptWindow = window

        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func dismissFromUser(muteForSession: Bool) {
        suppressDismissNotification = true
        promptWindow?.orderOut(nil)
        promptWindow?.contentViewController = nil
        promptWindow = nil
        suppressDismissNotification = false
        manager?.handlePermissionPromptDismissed(muteForSession: muteForSession)
        manager = nil
    }

    public func close() {
        precondition(Thread.isMainThread)
        suppressDismissNotification = true
        promptWindow?.orderOut(nil)
        promptWindow?.contentViewController = nil
        promptWindow = nil
        suppressDismissNotification = false
        manager = nil
    }

    public func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == promptWindow {
            promptWindow?.contentViewController = nil
            promptWindow = nil
            if !suppressDismissNotification {
                manager?.handlePermissionPromptDismissed(muteForSession: false)
            }
            manager = nil
        }
    }
}
