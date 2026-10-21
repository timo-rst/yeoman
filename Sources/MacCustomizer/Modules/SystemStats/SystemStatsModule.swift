import SwiftUI
import AppKit

public final class SystemStatsModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "system_stats"
    public let name = "Mini Task-Manager & System-Stats"
    public let moduleDescription = "CPU-, RAM- und GPU-Metriken in der Menüleiste mit Mini Task-Manager zum Abschießen von Prozessen."
    public let iconName = "gauge.with.needle"
    public let category = ModuleCategory.system
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "system_stats_is_enabled")
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }
    
    @Published public var showsDedicatedStatusItem: Bool {
        didSet {
            UserDefaults.standard.set(showsDedicatedStatusItem, forKey: "system_stats_shows_dedicated_status_item")
            updateStatusItemVisibility()
        }
    }
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "system_stats_is_enabled") as? Bool ?? true
        // Default to true so the widget is immediately visible
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "system_stats_shows_dedicated_status_item") as? Bool ?? true
        super.init()
    }
    
    public func start() {
        guard isEnabled else { return }
        SystemMetricsProvider.shared.startPolling()
        updateStatusItemVisibility()
    }
    
    public func stop() {
        SystemMetricsProvider.shared.stopPolling()
        removeStatusItem()
    }
    
    public func updateStatusItemVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isEnabled && self.showsDedicatedStatusItem {
                self.setupStatusItem()
            } else {
                self.removeStatusItem()
            }
        }
    }
    
    private func setupStatusItem() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "System Monitor & Mini Task-Manager (Klick zum Öffnen)"
            
            let widgetView = MenuBarStatsWidgetView().allowsHitTesting(false)
            let hostingView = NSHostingView(rootView: widgetView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
        self.statusItem = item
    }
    
    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        if let popover = popover, popover.isShown {
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
            p.contentSize = NSSize(width: 440, height: 490)
            p.behavior = .transient
            p.animates = true
            p.contentViewController = NSHostingController(rootView: TaskManagerPopoverView())
            self.popover = p
        }
        
        guard let p = popover else { return }
        if p.isShown {
            p.performClose(sender)
        } else {
            SystemMetricsProvider.shared.refreshMetrics()
            SystemMetricsProvider.shared.refreshProcessList()
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func showContextMenu(for sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Mini Task-Manager öffnen", action: #selector(openPopoverAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "macOS Aktivitätsanzeige öffnen", action: #selector(openActivityMonitorAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Einstellungen...", action: #selector(openSettingsAction), keyEquivalent: ","))
        
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
    
    @objc private func openActivityMonitorAction() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }
    
    public func settingsView() -> AnyView {
        AnyView(SystemStatsSettingsView(module: self))
    }
}

public struct SystemStatsSettingsView: View {
    @ObservedObject var module: SystemStatsModule
    @ObservedObject var provider = SystemMetricsProvider.shared
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Monitor & Mini Task-Manager")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Kompakte GPU-, RAM- und CPU-Graphen in der Menüleiste (wie in Stats) mit integriertem Mini Task-Manager (wie bei Windows) zum sofortigen Beenden und Abschießen hängender Prozesse.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Menüleisten-Option
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Widget")
                        .font(.headline)
                    
                    Toggle("Mini-Graphen & Metriken in Menüleiste anzeigen", isOn: $module.showsDedicatedStatusItem)
                        .font(.subheadline)
                    
                    Text("Rendert kompakte Live-Graphen für GPU, RAM und CPU nebeneinander direkt in der Menüleiste. Klick darauf öffnet den Mini Task-Manager.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Live Snapshot Preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Aktuelle System-Auslastung")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        MetricInfoBox(title: "CPU", value: "\(Int(provider.cpuUsagePercent))%", subtitle: "\(ProcessInfo.processInfo.processorCount) Cores", color: .blue)
                        MetricInfoBox(title: "RAM", value: "\(Int(provider.memoryUsagePercent))%", subtitle: "\(String(format: "%.1f", provider.memoryUsedGB)) GB", color: .purple)
                        MetricInfoBox(title: "GPU", value: "\(Int(provider.gpuUsagePercent))%", subtitle: "Metal Engine", color: .green)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Process Management Information
                VStack(alignment: .leading, spacing: 12) {
                    Text("Prozess-Verwaltung (Task-Manager)")
                        .font(.headline)
                    
                    Text("Aktuell laufen \(provider.processes.count) Prozesse auf deinem Mac. Über den Mini Task-Manager kannst du hungrige oder nicht reagierende Prozesse mit einem einzigen Klick per SIGKILL sofort beenden.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Aktivitätsanzeige öffnen") {
                            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
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

struct MetricInfoBox: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
    }
}
