import SwiftUI
import AppKit
import Combine

public enum StatsLayoutMode: String, CaseIterable, Codable {
    case vertical = "Vertikal gestapelt (wie Stats)"
    case horizontal = "Horizontal nebeneinander"
}

public enum StatsGraphStyle: String, CaseIterable, Codable {
    case miniBar = "Vertikaler Füllbalken"
    case sparkline = "Mini-Verlaufskurve"
    case none = "Kein Graph"
}

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
    
    @Published public var layoutMode: StatsLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: "stats_layout_mode")
            updateStatusItemLength()
        }
    }
    @Published public var graphStyle: StatsGraphStyle {
        didSet {
            UserDefaults.standard.set(graphStyle.rawValue, forKey: "stats_graph_style")
            updateStatusItemLength()
        }
    }
    @Published public var showCPU: Bool {
        didSet {
            UserDefaults.standard.set(showCPU, forKey: "stats_show_cpu")
            updateStatusItemLength()
        }
    }
    @Published public var showRAM: Bool {
        didSet {
            UserDefaults.standard.set(showRAM, forKey: "stats_show_ram")
            updateStatusItemLength()
        }
    }
    @Published public var showGPU: Bool {
        didSet {
            UserDefaults.standard.set(showGPU, forKey: "stats_show_gpu")
            updateStatusItemLength()
        }
    }
    @Published public var showLabels: Bool {
        didSet {
            UserDefaults.standard.set(showLabels, forKey: "stats_show_labels")
            updateStatusItemLength()
        }
    }
    @Published public var showPercentage: Bool {
        didSet {
            UserDefaults.standard.set(showPercentage, forKey: "stats_show_percentage")
            updateStatusItemLength()
        }
    }
    @Published public var showGraphs: Bool {
        didSet {
            UserDefaults.standard.set(showGraphs, forKey: "stats_show_graphs")
            updateStatusItemLength()
        }
    }
    @Published public var useSubtleBackground: Bool {
        didSet {
            UserDefaults.standard.set(useSubtleBackground, forKey: "stats_use_subtle_background")
            updateStatusItemLength()
        }
    }
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var spacingCancellable: AnyCancellable?
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "system_stats_is_enabled") as? Bool ?? true
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "system_stats_shows_dedicated_status_item") as? Bool ?? true
        
        if let savedLayout = UserDefaults.standard.string(forKey: "stats_layout_mode"),
           let l = StatsLayoutMode(rawValue: savedLayout) {
            self.layoutMode = l
        } else {
            self.layoutMode = .vertical
        }
        
        if let savedGraphStyle = UserDefaults.standard.string(forKey: "stats_graph_style"),
           let g = StatsGraphStyle(rawValue: savedGraphStyle) {
            self.graphStyle = g
        } else {
            self.graphStyle = .miniBar
        }
        
        self.showCPU = UserDefaults.standard.object(forKey: "stats_show_cpu") as? Bool ?? true
        self.showRAM = UserDefaults.standard.object(forKey: "stats_show_ram") as? Bool ?? true
        self.showGPU = UserDefaults.standard.object(forKey: "stats_show_gpu") as? Bool ?? true
        self.showLabels = UserDefaults.standard.object(forKey: "stats_show_labels") as? Bool ?? true
        self.showPercentage = UserDefaults.standard.object(forKey: "stats_show_percentage") as? Bool ?? true
        self.showGraphs = UserDefaults.standard.object(forKey: "stats_show_graphs") as? Bool ?? true
        self.useSubtleBackground = UserDefaults.standard.object(forKey: "stats_use_subtle_background") as? Bool ?? false
        
        super.init()
        
        // Dynamically adjust status item length when menu bar spacing changes
        self.spacingCancellable = MenuBarSpacingManager.shared.$currentSpacing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemLength()
            }
        
        // Listen for system / window / space changes to automatically recover status item if needed
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnvironmentChange), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnvironmentChange), name: NSWindow.didChangeScreenNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnvironmentChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
    
    @objc private func handleEnvironmentChange() {
        ensureStatusItemVisible()
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
    
    public func calculatedStatusItemWidth() -> CGFloat {
        let activeMetricsCount = (showCPU ? 1 : 0) + (showRAM ? 1 : 0) + (showGPU ? 1 : 0)
        if activeMetricsCount == 0 {
            // When all individual metrics are toggled off, show the fallback icon & title
            return showLabels ? 46.0 : 24.0
        }
        
        let interItemSpacing: CGFloat = CGFloat(max(2, MenuBarSpacingManager.shared.currentSpacing))
        let paddingPerItem: CGFloat = useSubtleBackground ? 8.0 : 4.0
        let outerPadding: CGFloat = 4.0
        
        if layoutMode == .vertical {
            // Vertical stacked layout (label top, percentage bottom, bar or sparkline right)
            var textW: CGFloat = 0
            if showLabels && showPercentage {
                textW = 21.5
            } else if showPercentage {
                textW = 21.5
            } else if showLabels {
                textW = 17.5
            }
            
            var graphW: CGFloat = 0
            if showGraphs && graphStyle != .none {
                graphW = (graphStyle == .sparkline) ? 18.0 : 4.5
            }
            
            let spacingBetweenTextAndGraph: CGFloat = (textW > 0 && graphW > 0) ? 3.0 : 0
            let singleItemW = textW + graphW + spacingBetweenTextAndGraph + paddingPerItem
            let total = (CGFloat(activeMetricsCount) * singleItemW) + (CGFloat(activeMetricsCount - 1) * interItemSpacing) + outerPadding
            return ceil(total)
        } else {
            // Horizontal layout (label, percentage, graph side by side)
            var componentsW: CGFloat = 0
            var count = 0
            if showLabels {
                componentsW += 19.0
                count += 1
            }
            if showPercentage {
                componentsW += 21.5
                count += 1
            }
            if showGraphs && graphStyle != .none {
                componentsW += (graphStyle == .sparkline) ? 20.0 : 16.0
                count += 1
            }
            
            let spacing: CGFloat = CGFloat(max(0, count - 1)) * 3.0
            let singleItemW = componentsW + spacing + paddingPerItem
            let total = (CGFloat(activeMetricsCount) * singleItemW) + (CGFloat(activeMetricsCount - 1) * interItemSpacing) + outerPadding
            return ceil(total)
        }
    }
    
    public func updateStatusItemLength() {
        guard let item = statusItem else { return }
        let targetLength = calculatedStatusItemWidth()
        DispatchQueue.main.async {
            if abs(item.length - targetLength) > 0.5 {
                item.length = targetLength
            }
        }
    }
    
    public func ensureStatusItemVisible() {
        guard isEnabled && showsDedicatedStatusItem else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.statusItem == nil || self.statusItem?.button?.window == nil {
                self.removeStatusItem()
                self.setupStatusItem()
            } else {
                self.updateStatusItemLength()
            }
        }
    }
    
    private func setupStatusItem() {
        if let existing = statusItem {
            if existing.button?.window != nil && !(existing.button?.subviews.isEmpty ?? true) {
                updateStatusItemLength()
                return
            }
            removeStatusItem()
        }
        
        let initialWidth = calculatedStatusItemWidth()
        let item = NSStatusBar.system.statusItem(withLength: initialWidth)
        if let button = item.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "System Monitor & Mini Task-Manager (Klick zum Öffnen)"
            
            let widgetView = MenuBarStatsWidgetView(isLiveMenuBar: true).allowsHitTesting(false)
            let hostingView = NSHostingView(rootView: widgetView)
            hostingView.frame = button.bounds
            hostingView.autoresizingMask = [.width, .height]
            button.addSubview(hostingView)
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
            p.contentSize = NSSize(width: 460, height: 495)
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
                    
                    Text("Rendert kompakte Live-Metriken für CPU, RAM und GPU direkt in der Menüleiste. Klick darauf öffnet den Mini Task-Manager.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Menüleisten-Anzeige Konfiguration
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Anzeige konfigurieren")
                        .font(.headline)
                    
                    // Live Vorschau
                    HStack {
                        Text("Live-Vorschau:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        MenuBarStatsWidgetView(isLiveMenuBar: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    
                    Divider()
                    
                    Text("Aktive Messwerte in der Menüleiste:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 24) {
                        Toggle("CPU", isOn: $module.showCPU)
                        Toggle("RAM (Speicher)", isOn: $module.showRAM)
                        Toggle("GPU (Grafik)", isOn: $module.showGPU)
                    }
                    
                    Divider()
                    
                    Text("Layout & Text-Ausrichtung:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Layout-Stil:", selection: $module.layoutMode) {
                        ForEach(StatsLayoutMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Graph-Typ:", selection: $module.graphStyle) {
                        ForEach(StatsGraphStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                    
                    Text("Darstellungs-Optionen:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Text-Bezeichnung anzeigen (z.B. „CPU“, „RAM“, „GPU“)", isOn: $module.showLabels)
                        Toggle("Prozentwert als Text anzeigen (z.B. „10%“, „61%“)", isOn: $module.showPercentage)
                        Toggle("Mini-Graphen & Balken anzeigen", isOn: $module.showGraphs)
                        Toggle("Dezenter Kapsel-Hintergrund (Pill)", isOn: $module.useSubtleBackground)
                    }
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
