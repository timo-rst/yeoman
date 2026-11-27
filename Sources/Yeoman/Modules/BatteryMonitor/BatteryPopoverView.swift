import AppKit
import SwiftUI

public struct BatteryPopoverView: View {
    @ObservedObject var provider: BatteryMetricsProvider
    @ObservedObject var l10nObj = LocalizationManager.shared
    @State private var selectedRange: BatteryTimeRange = .twentyFourHours
    @State private var hasPickedInitialRange = false
    @State private var hoveredSlotIndex: Int? = nil
    private let pinPreference: PopoverPinPreference?

    public init(
        provider: BatteryMetricsProvider = .shared,
        pinPreference: PopoverPinPreference? = nil
    ) {
        self.provider = provider
        self.pinPreference = pinPreference
    }

    private var activeRangeForDisplay: BatteryTimeRange {
        selectedRange
    }

    private var displayedEntries: [AppEnergyEntry] {
        provider.entries(for: activeRangeForDisplay)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    chartsSection
                    appEnergySection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            Divider()
            footerSection
        }
        .frame(width: 460, height: 600)
        .onAppear {
            if !hasPickedInitialRange {
                hasPickedInitialRange = true
                if !provider.twentyFourHourEntries.isEmpty {
                    selectedRange = .twentyFourHours
                } else if !provider.sessionEntries.isEmpty {
                    selectedRange = .sinceLaunch
                } else {
                    selectedRange = .live
                }
            }
            provider.startLivePolling()
        }
        .onDisappear {
            provider.stopLivePolling()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                BatteryGlyphView(
                    chargePercent: provider.hardware.chargePercent,
                    isCharging: provider.hardware.isCharging,
                    isExternalConnected: provider.hardware.isExternalConnected,
                    isLowPowerMode: provider.hardware.isLowPowerMode,
                    width: 40,
                    height: 19
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(provider.hardware.hasBattery ? "\(provider.hardware.chargePercent)%" : "--%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text(powerStateDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        if provider.hardware.isLowPowerMode {
                            Text(l10n("battery.low_power_mode"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundColor(.orange)
                        }
                    }

                    HStack(spacing: 8) {
                        if provider.hardware.hasBattery {
                            Label(formattedWattage(provider.hardware.powerWatts), systemImage: provider.hardware.isCharging ? "bolt.fill" : "flame")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(provider.hardware.isCharging ? .green : .secondary)

                            if let rem = provider.hardware.timeRemainingMinutes {
                                Text("•  \(formattedMinutes(rem))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(l10n("battery.no_battery"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: { provider.refreshNow() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help(l10n("battery.refresh_tooltip"))

                    if let pinPref = pinPreference {
                        PopoverPinButton(preference: pinPref)
                    }
                }
            }

            if provider.hardware.hasBattery {
                HStack(spacing: 8) {
                    HardwareStatPill(
                        label: l10n("battery.health"),
                        value: String(format: "%.0f%%", provider.hardware.batteryHealthPercent)
                    )
                    HardwareStatPill(
                        label: l10n("battery.cycles"),
                        value: "\(provider.hardware.cycleCount)"
                    )
                    HardwareStatPill(
                        label: l10n("battery.temp"),
                        value: String(format: "%.1f °C", provider.hardware.temperatureCelsius)
                    )
                    HardwareStatPill(
                        label: l10n("battery.capacity"),
                        value: "\(provider.hardware.rawCurrentMah) / \(provider.hardware.nominalMaxMah) mAh"
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var powerStateDescription: String {
        guard provider.hardware.hasBattery else { return l10n("battery.ac_only") }
        if provider.hardware.isCharging { return l10n("battery.charging") }
        if provider.hardware.isExternalConnected && provider.hardware.isFullyCharged { return l10n("battery.fully_charged") }
        if provider.hardware.isExternalConnected { return l10n("battery.on_ac") }
        return l10n("battery.on_battery")
    }

    private func formattedWattage(_ watts: Double) -> String {
        let sign = watts > 0.05 ? "+" : (watts < -0.05 ? "-" : "")
        return String(format: "%@%.1f W", sign, abs(watts))
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        return "\(m)m"
    }

    // MARK: - 24h Battery Level & Screen Usage Charts

    private var chartsSection: some View {
        let slotEpochs = makeLast96SlotEpochs(now: Date())
        let bucketMap = Dictionary(uniqueKeysWithValues: provider.buckets.map { ($0.bucketStartEpoch, $0) })

        return VStack(alignment: .leading, spacing: 12) {
            // 1. Batteriestatus (24h, 96 x 15-min bars)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(l10n("battery.chart_status"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let idx = hoveredSlotIndex, idx >= 0, idx < slotEpochs.count {
                        let epoch = slotEpochs[idx]
                        Text(hoverLabel(epoch: epoch, bucket: bucketMap[epoch]))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else if provider.isBootstrappingHistory {
                        Text(l10n("battery.loading_history"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }

                BatteryStatus24hChart(
                    slotEpochs: slotEpochs,
                    bucketMap: bucketMap,
                    selectedBucketEpoch: provider.selectedBucketEpoch,
                    hoveredSlotIndex: $hoveredSlotIndex,
                    onSelectBucket: { epoch in
                        if provider.selectedBucketEpoch == epoch {
                            provider.selectBucket(nil)
                        } else {
                            provider.selectBucket(epoch)
                            if selectedRange == .live || selectedRange == .sinceLaunch {
                                selectedRange = .twentyFourHours
                            }
                        }
                    }
                )
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            // 2. Nutzung bei eingeschaltetem Bildschirm (24 x 1h bars)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(l10n("battery.chart_screen_on"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    let totalMinutes = provider.hourlyScreenUsage.reduce(0) { $0 + $1.minutes }
                    Text(String(format: "%@: %dh %02dm", l10n("battery.total_24h"), totalMinutes / 60, totalMinutes % 60))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }

                ScreenOnUsage24hChart(bars: ensure24Bars(provider.hourlyScreenUsage))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func makeLast96SlotEpochs(now: Date) -> [Int64] {
        let alignedNow = BatteryHistoryBucket.alignEpoch(now)
        let first = alignedNow - Int64(BatteryPersistedHistory.maxBuckets - 1) * BatteryHistoryBucket.durationSeconds
        return (0..<BatteryPersistedHistory.maxBuckets).map { first + Int64($0) * BatteryHistoryBucket.durationSeconds }
    }

    private func ensure24Bars(_ existing: [HourlyScreenUsageBar]) -> [HourlyScreenUsageBar] {
        if existing.count == 24 { return existing }
        return AppEnergyAggregator.hourlyScreenUsage(buckets: provider.buckets, now: Date())
    }

    private func hoverLabel(epoch: Int64, bucket: BatteryHistoryBucket?) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(epoch))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = formatter.string(from: start)
        if let bucket {
            let state = bucket.wasCharging ? l10n("battery.charging_short") : l10n("battery.on_battery_short")
            return "\(timeStr)  \(bucket.lastChargePercent)% (\(state))"
        }
        return "\(timeStr)  --"
    }

    // MARK: - App Energy Breakdown

    private var appEnergySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(l10n("battery.app_usage_title"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let bucketEpoch = provider.selectedBucketEpoch,
                   selectedRange != .live && selectedRange != .sinceLaunch {
                    Button(action: { provider.selectBucket(nil) }) {
                        HStack(spacing: 4) {
                            Text(slotRangeLabel(bucketEpoch))
                            Image(systemName: "xmark.circle.fill")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Segmented Time Range Picker
            HStack(spacing: 2) {
                ForEach(BatteryTimeRange.allCases) { range in
                    let isSelected = selectedRange == range
                    Button(action: {
                        selectedRange = range
                        if range == .live || range == .sinceLaunch {
                            provider.selectBucket(nil)
                        }
                    }) {
                        Text(range.localizedTitle)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                    .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 1, y: 0.5)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))

            let entries = displayedEntries
            let maxMetric = entries.map { activeRangeForDisplay == .live ? ($0.liveWatts ?? 0) : $0.energyWh }.max() ?? 1.0

            if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(l10n("battery.no_app_samples_yet"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(entries.prefix(20))) { entry in
                        AppEnergyRow(
                            entry: entry,
                            maxValue: maxMetric,
                            isLiveMode: activeRangeForDisplay == .live
                        )
                    }
                }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    private func slotRangeLabel(_ epoch: Int64) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(epoch))
        let end = Date(timeIntervalSince1970: TimeInterval(epoch + BatteryHistoryBucket.durationSeconds))
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: start))–\(fmt.string(from: end))"
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text(recordingSinceLabel)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            Spacer()

            Button(l10n("battery.open_macos_settings")) {
                openSystemBatterySettings()
            }
            .font(.system(size: 11))
            .buttonStyle(.link)

            Text("·")
                .foregroundColor(.secondary.opacity(0.5))

            Button(l10n("battery.yeoman_settings")) {
                StatusItemController.shared.openSettingsWindow()
            }
            .font(.system(size: 11))
            .buttonStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var recordingSinceLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return String(format: l10n("battery.recording_since_format"), fmt.string(from: provider.recordingStartedAt))
    }

    private func openSystemBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

// MARK: - Supporting UI Components

public struct BatteryGlyphView: View {
    let chargePercent: Int
    let isCharging: Bool
    let isExternalConnected: Bool
    let isLowPowerMode: Bool
    let width: CGFloat
    let height: CGFloat

    private var fillColor: Color {
        if isCharging { return .green }
        if isLowPowerMode { return .orange }
        if chargePercent <= 20 { return .red }
        return .green
    }

    public var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.24, style: .continuous)
                    .stroke(Color.primary.opacity(0.45), lineWidth: 1.2)
                    .frame(width: width - 4, height: height)

                let innerMax = max(2, width - 8)
                let fillWidth = max(2, innerMax * CGFloat(min(100, max(0, chargePercent))) / 100.0)
                RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                    .fill(fillColor)
                    .frame(width: fillWidth, height: max(2, height - 4))
                    .padding(.leading, 2)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.58, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(width: width - 4, height: height)
                } else if isExternalConnected {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: height * 0.48, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(width: width - 4, height: height)
                }
            }

            // Battery nub
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.primary.opacity(0.45))
                .frame(width: 2.2, height: height * 0.42)
        }
    }
}

private struct HardwareStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}

private struct BatteryStatus24hChart: View {
    let slotEpochs: [Int64]
    let bucketMap: [Int64: BatteryHistoryBucket]
    let selectedBucketEpoch: Int64?
    @Binding var hoveredSlotIndex: Int?
    let onSelectBucket: (Int64) -> Void

    private let chartHeight: CGFloat = 86

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                GeometryReader { geo in
                    let plotWidth = geo.size.width
                    let count = CGFloat(max(1, slotEpochs.count))
                    let step = plotWidth / count
                    let barWidth = max(1.5, step * 0.62)

                    ZStack(alignment: .bottomLeading) {
                        // Dashed horizontal gridlines at 0%, 50%, 100%
                        ForEach([0.0, 0.5, 1.0], id: \.self) { frac in
                            Path { p in
                                let y = chartHeight * (1.0 - frac)
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: plotWidth, y: y))
                            }
                            .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
                        }

                        // Charging background bands + bars
                        ForEach(Array(slotEpochs.enumerated()), id: \.offset) { idx, epoch in
                            let x = CGFloat(idx) * step
                            let bucket = bucketMap[epoch]
                            let isSelected = selectedBucketEpoch == epoch
                            let isHovered = hoveredSlotIndex == idx

                            ZStack(alignment: .bottom) {
                                if let b = bucket, b.wasCharging || b.wasExternalConnected {
                                    Rectangle()
                                        .fill(Color.green.opacity(0.16))
                                        .frame(width: ceil(step), height: chartHeight)
                                }

                                if isSelected || isHovered {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(isSelected ? 0.24 : 0.14))
                                        .frame(width: ceil(step), height: chartHeight)
                                }

                                if let b = bucket {
                                    let pct = CGFloat(min(100, max(2, b.lastChargePercent))) / 100.0
                                    RoundedRectangle(cornerRadius: barWidth * 0.4, style: .continuous)
                                        .fill(b.lastChargePercent <= 20 ? Color.red : Color.green)
                                        .frame(width: barWidth, height: max(2, chartHeight * pct))
                                } else {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: barWidth, height: 2)
                                }
                            }
                            .frame(width: step, height: chartHeight, alignment: .bottom)
                            .offset(x: x)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredSlotIndex = hovering ? idx : (hoveredSlotIndex == idx ? nil : hoveredSlotIndex)
                            }
                            .onTapGesture {
                                onSelectBucket(epoch)
                            }
                        }

                        // Bottom charging bar strips
                        ForEach(Array(slotEpochs.enumerated()), id: \.offset) { idx, epoch in
                            if let b = bucketMap[epoch], b.wasCharging {
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: ceil(step), height: 3)
                                    .offset(x: CGFloat(idx) * step, y: 5)
                            }
                        }
                    }
                }
                .frame(height: chartHeight)

                VStack {
                    Text("100%")
                    Spacer()
                    Text("50%")
                    Spacer()
                    Text("0%")
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 34, height: chartHeight, alignment: .trailing)
            }

            HourAxisLabelsRow(startEpoch: slotEpochs.first ?? 0)
                .padding(.trailing, 40)
        }
    }
}

private struct ScreenOnUsage24hChart: View {
    let bars: [HourlyScreenUsageBar]
    private let chartHeight: CGFloat = 68

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                GeometryReader { geo in
                    let plotWidth = geo.size.width
                    let count = CGFloat(max(1, bars.count))
                    let step = plotWidth / count
                    let barWidth = max(4, step * 0.56)

                    ZStack(alignment: .bottomLeading) {
                        ForEach([0.0, 0.5, 1.0], id: \.self) { frac in
                            Path { p in
                                let y = chartHeight * (1.0 - frac)
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: plotWidth, y: y))
                            }
                            .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
                        }

                        ForEach(Array(bars.enumerated()), id: \.element.id) { idx, bar in
                            let frac = CGFloat(min(60, max(0, bar.minutes))) / 60.0
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(bar.minutes > 0 ? Color.blue : Color.primary.opacity(0.08))
                                .frame(width: barWidth, height: bar.minutes > 0 ? max(3, chartHeight * frac) : 2)
                                .frame(width: step, height: chartHeight, alignment: .bottom)
                                .offset(x: CGFloat(idx) * step)
                                .help("\(hourLabel(bar.hourStart)): \(bar.minutes) min")
                        }
                    }
                }
                .frame(height: chartHeight)

                VStack {
                    Text("60m")
                    Spacer()
                    Text("30m")
                    Spacer()
                    Text("0m")
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 34, height: chartHeight, alignment: .trailing)
            }

            if let first = bars.first?.hourStart, let last = bars.last?.hourStart {
                HourAxisLabelsRow(startEpoch: Int64(first.timeIntervalSince1970), endDate: last)
                    .padding(.trailing, 40)
            }
        }
    }

    private func hourLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:00"
        return fmt.string(from: date)
    }
}

private struct HourAxisLabelsRow: View {
    let startEpoch: Int64
    var endDate: Date? = nil

    var body: some View {
        let calendar = Calendar.current
        let base = Date(timeIntervalSince1970: TimeInterval(startEpoch))
        HStack {
            ForEach(0..<8, id: \.self) { step in
                let d = calendar.date(byAdding: .hour, value: step * 3, to: base) ?? base
                Text(hourText(d))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                if step < 7 {
                    Spacer()
                }
            }
        }
    }

    private func hourText(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH"
        return fmt.string(from: date)
    }
}

// MARK: - App Energy Row & Icon Cache

private final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for bundlePath: String?) -> NSImage {
        guard let bundlePath else {
            return NSWorkspace.shared.icon(for: .unixExecutable)
        }
        if let cached = cache[bundlePath] {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: bundlePath)
        cache[bundlePath] = img
        return img
    }
}

private struct AppEnergyRow: View {
    let entry: AppEnergyEntry
    let maxValue: Double
    let isLiveMode: Bool

    private var metricValue: Double {
        isLiveMode ? (entry.liveWatts ?? 0) : entry.energyWh
    }

    private var barFraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(min(1.0, max(0.03, metricValue / maxValue)))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconCache.shared.icon(for: entry.bundlePath))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if entry.isSignificant {
                        Text(l10n("battery.significant_badge"))
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)
                        Capsule()
                            .fill(entry.isSignificant ? Color.orange : Color.green)
                            .frame(width: max(4, geo.size.width * barFraction), height: 4)
                    }
                }
                .frame(height: 4)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(primaryMetricText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(entry.isSignificant ? .orange : .primary)

                Text(secondaryMetricText)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 82, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var primaryMetricText: String {
        if isLiveMode {
            return String(format: "%.1f W", entry.liveWatts ?? 0)
        }
        if entry.energyWh >= 0.1 {
            return String(format: "%.2f Wh", entry.energyWh)
        }
        return String(format: "%.0f mWh", entry.energyWh * 1000.0)
    }

    private var secondaryMetricText: String {
        if isLiveMode {
            return String(format: "%.0f%% %@", entry.sharePercent, l10n("battery.share_short"))
        }
        return String(format: "~%.1f%% • %.0f%%", entry.estimatedBatteryPercent, entry.sharePercent)
    }
}
