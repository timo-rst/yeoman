import AppKit
import Combine
import SwiftUI

public final class BatteryMonitorModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "battery_monitor"
    public let name = "Batterie-Monitor"
    public let moduleDescription = "Akkuverlauf über 24 Stunden, Bildschirmnutzung und pro-App Energieverbrauch direkt in der Menüleiste."
    public let iconName = "battery.75"
    public let category = ModuleCategory.system

    private static let enabledDefaultsKey = "battery_monitor_is_enabled"

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                start()
            } else {
                stop()
            }
            ModuleManager.shared.objectWillChange.send()
            ModuleManager.shared.recreateAllStatusItems()
        }
    }

    public var showsDedicatedStatusItem: Bool {
        get { isEnabled }
        set {
            if isEnabled != newValue {
                isEnabled = newValue
            }
        }
    }

    @Published public var menuBarStyle: BatteryMenuBarStyle {
        didSet {
            UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "battery_monitor_style")
            updateStatusItemLength()
        }
    }

    public let popoverPin = PopoverPinPreference(storageKey: "battery_monitor_popover_pinned")
    private var statusItem: NSStatusItem?
    private var statusHostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var popover: NSPopover?
    private var pinCancellable: AnyCancellable?

    public override init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: Self.enabledDefaultsKey) as? Bool {
            self.isEnabled = stored
        } else {
            self.isEnabled = BatteryMetricsProvider.hardwareHasBattery()
        }

        if let rawStyle = defaults.string(forKey: "battery_monitor_style"),
           let parsed = BatteryMenuBarStyle(rawValue: rawStyle) {
            self.menuBarStyle = parsed
        } else {
            self.menuBarStyle = .iconAndPercent
        }

        super.init()

        pinCancellable = popoverPin.$isPinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPinned in
                self?.popover?.behavior = isPinned ? .applicationDefined : .transient
            }
    }

    public func start() {
        guard isEnabled else { return }
        BatteryMetricsProvider.shared.start()
        setupStatusItem()
        subscribeToHardwareChanges()
    }

    public func stop() {
        BatteryMetricsProvider.shared.stop()
        cancellables.removeAll()
        removeStatusItem()
    }

    private func subscribeToHardwareChanges() {
        guard cancellables.isEmpty else { return }
        BatteryMetricsProvider.shared.$hardware
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemLength()
            }
            .store(in: &cancellables)
    }

    public func updateStatusItemVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isEnabled && self.showsDedicatedStatusItem {
                self.setupStatusItem()
            } else {
                self.removeStatusItem()
            }
        }
    }

    public func calculatedStatusItemWidth() -> CGFloat {
        switch menuBarStyle {
        case .iconOnly: return 24.0
        case .percentOnly: return 28.0
        case .iconAndPercent: return 53.0
        case .iconPercentWatts: return 86.0
        }
    }

    public func updateStatusItemLength() {
        guard let item = statusItem else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let measured = self.statusHostingView.map { ceil($0.fittingSize.width) } ?? 0
            let target = max(18.0, measured > 1 ? measured : self.calculatedStatusItemWidth())
            if abs(item.length - target) > 0.5 {
                item.length = target
            }
        }
    }

    public func setupStatusItem() {
        guard isEnabled && showsDedicatedStatusItem else { return }
        if let existing = statusItem {
            if !(existing.button?.subviews.isEmpty ?? true) {
                updateStatusItemLength()
                return
            }
            removeStatusItem()
        }

        let widgetView = AnyView(MenuBarBatteryWidgetView(module: self).allowsHitTesting(false))
        let hosting = NSHostingView(rootView: widgetView)
        let measured = ceil(hosting.fittingSize.width)
        let initialWidth = max(18.0, measured > 1 ? measured : calculatedStatusItemWidth())

        let item = NSStatusBar.system.statusItem(withLength: initialWidth)
        if let button = item.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = l10n("battery.menubar_tooltip")

            hosting.frame = button.bounds
            hosting.autoresizingMask = [.width, .height]
            button.addSubview(hosting)
        }
        self.statusHostingView = hosting
        self.statusItem = item
    }

    public func removeStatusItem() {
        statusHostingView = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        if let popover, popover.isShown {
            popover.performClose(nil)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(for: sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let p = NSPopover()
            p.contentSize = NSSize(width: 460, height: 600)
            p.behavior = popoverPin.popoverBehavior
            p.animates = true
            p.delegate = self
            p.contentViewController = NSHostingController(rootView: BatteryPopoverView(pinPreference: popoverPin))
            self.popover = p
        }

        guard let p = popover else { return }
        if p.isShown {
            p.performClose(sender)
        } else {
            PopoverFocusCoordinator.shared.prepareForPresentation(of: p)
            BatteryMetricsProvider.shared.refreshNow()
            BatteryMetricsProvider.shared.startLivePolling()
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func showContextMenu(for sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: l10n("battery.menu_open_overview"), action: #selector(openPopoverAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: l10n("battery.open_macos_settings"), action: #selector(openMacOSBatterySettingsAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: l10n("menu.settings"), action: #selector(openSettingsAction), keyEquivalent: ","))

        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openPopoverAction() {
        if let button = statusItem?.button {
            togglePopover(button)
        }
    }

    @objc private func openMacOSBatterySettingsAction() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }

    public func settingsView() -> AnyView {
        AnyView(BatteryMonitorSettingsView(module: self))
    }
}

extension BatteryMonitorModule: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        PopoverFocusCoordinator.shared.handlePopoverDidClose(of: popover)
        BatteryMetricsProvider.shared.stopLivePolling()
        guard let closedPopover = notification.object as? NSPopover else { return }
        closedPopover.contentViewController = nil
        closedPopover.delegate = nil
        if popover === closedPopover {
            popover = nil
        }
    }
}

// MARK: - Menu Bar Widget View

public struct MenuBarBatteryWidgetView: View {
    @ObservedObject var module: BatteryMonitorModule
    @ObservedObject var provider = BatteryMetricsProvider.shared

    public var body: some View {
        let hw = provider.hardware
        HStack(spacing: 3) {
            if module.menuBarStyle != .percentOnly {
                BatteryGlyphView(
                    chargePercent: hw.chargePercent,
                    isCharging: hw.isCharging,
                    isExternalConnected: hw.isExternalConnected,
                    isLowPowerMode: hw.isLowPowerMode,
                    width: 22,
                    height: 11
                )
            }

            if module.menuBarStyle != .iconOnly {
                Text(hw.hasBattery ? "\(hw.chargePercent)%" : "--%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }

            if module.menuBarStyle == .iconPercentWatts && hw.hasBattery {
                let sign = hw.powerWatts > 0.05 ? "+" : (hw.powerWatts < -0.05 ? "-" : "")
                Text(String(format: "%@%.0fW", sign, abs(hw.powerWatts)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(hw.isCharging ? .green : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 22)
    }
}

// MARK: - Module Settings View

public struct BatteryMonitorSettingsView: View {
    @ObservedObject var module: BatteryMonitorModule
    @ObservedObject var provider = BatteryMetricsProvider.shared
    @ObservedObject var l10nObj = LocalizationManager.shared

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: module.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n("tab.batteryMonitor"))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(l10n("battery.settings_subtitle"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { module.isEnabled },
                    set: { ModuleManager.shared.toggleModule(id: module.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Display Style Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(l10n("battery.menubar_display"))
                                .font(.headline)
                            Spacer()
                            MenuBarBatteryWidgetView(module: module)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.75)))
                        }

                        Picker("", selection: $module.menuBarStyle) {
                            ForEach(BatteryMenuBarStyle.allCases) { style in
                                Text(style.localizedTitle).tag(style)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                    // Hardware Diagnostics Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(l10n("battery.hardware_diagnostics"))
                                .font(.headline)
                            Spacer()
                            Button(l10n("battery.refresh_tooltip")) {
                                provider.refreshNow()
                            }
                            .font(.caption)
                        }

                        if provider.hardware.hasBattery {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    Text(l10n("battery.health")).foregroundColor(.secondary)
                                    Text(String(format: "%.1f%% (%d / %d mAh)", provider.hardware.batteryHealthPercent, provider.hardware.nominalMaxMah, provider.hardware.designCapacityMah))
                                        .fontWeight(.medium)
                                    Text(l10n("battery.cycles")).foregroundColor(.secondary)
                                    Text("\(provider.hardware.cycleCount)").fontWeight(.medium)
                                }
                                GridRow {
                                    Text(l10n("battery.power_flow")).foregroundColor(.secondary)
                                    Text(String(format: "%+.2f W (%.2f V, %+.2f A)", provider.hardware.powerWatts, provider.hardware.voltageVolts, provider.hardware.amperageAmps))
                                        .fontWeight(.medium)
                                    Text(l10n("battery.temp")).foregroundColor(.secondary)
                                    Text(String(format: "%.1f °C", provider.hardware.temperatureCelsius)).fontWeight(.medium)
                                }
                            }
                            .font(.subheadline)
                        } else {
                            Text(l10n("battery.no_battery"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                    // History & Storage Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n("battery.history_storage"))
                            .font(.headline)

                        Text(l10n("battery.history_storage_desc"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            Button(role: .destructive) {
                                provider.clearHistory()
                            } label: {
                                Label(l10n("battery.clear_history"), systemImage: "trash")
                            }
                            Spacer()
                            Button(l10n("battery.open_macos_settings")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .padding(20)
            }
        }
    }
}
