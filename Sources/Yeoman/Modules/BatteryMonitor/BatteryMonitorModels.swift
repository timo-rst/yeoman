import Foundation

public enum BatteryTimeRange: String, CaseIterable, Identifiable {
    case live = "live"
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"
    case sinceLaunch = "sinceLaunch"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .live: return l10n("battery.range_live")
        case .oneHour: return l10n("battery.range_1h")
        case .sixHours: return l10n("battery.range_6h")
        case .twentyFourHours: return l10n("battery.range_24h")
        case .sinceLaunch: return l10n("battery.range_since_launch")
        }
    }
}

public enum BatteryMenuBarStyle: String, CaseIterable, Codable, Identifiable {
    case iconAndPercent = "icon_and_percent"
    case iconPercentWatts = "icon_percent_watts"
    case iconOnly = "icon_only"
    case percentOnly = "percent_only"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .iconAndPercent: return l10n("battery.style_icon_percent")
        case .iconPercentWatts: return l10n("battery.style_icon_percent_watts")
        case .iconOnly: return l10n("battery.style_icon_only")
        case .percentOnly: return l10n("battery.style_percent_only")
        }
    }
}

public struct BatteryHardwareSnapshot: Equatable {
    public let hasBattery: Bool
    public let chargePercent: Int
    public let rawCurrentMah: Int
    public let rawMaxMah: Int
    public let nominalMaxMah: Int
    public let designCapacityMah: Int
    public let batteryHealthPercent: Double
    public let cycleCount: Int
    public let voltageVolts: Double
    public let amperageAmps: Double
    public let powerWatts: Double
    public let temperatureCelsius: Double
    public let isCharging: Bool
    public let isExternalConnected: Bool
    public let isFullyCharged: Bool
    public let timeRemainingMinutes: Int?
    public let isLowPowerMode: Bool
    public let isDisplayAwake: Bool
    public let timestamp: Date

    public init(
        hasBattery: Bool,
        chargePercent: Int,
        rawCurrentMah: Int,
        rawMaxMah: Int,
        nominalMaxMah: Int,
        designCapacityMah: Int,
        batteryHealthPercent: Double,
        cycleCount: Int,
        voltageVolts: Double,
        amperageAmps: Double,
        powerWatts: Double,
        temperatureCelsius: Double,
        isCharging: Bool,
        isExternalConnected: Bool,
        isFullyCharged: Bool,
        timeRemainingMinutes: Int?,
        isLowPowerMode: Bool,
        isDisplayAwake: Bool,
        timestamp: Date
    ) {
        self.hasBattery = hasBattery
        self.chargePercent = min(100, max(0, chargePercent))
        self.rawCurrentMah = max(0, rawCurrentMah)
        self.rawMaxMah = max(0, rawMaxMah)
        self.nominalMaxMah = max(0, nominalMaxMah)
        self.designCapacityMah = max(0, designCapacityMah)
        self.batteryHealthPercent = min(120, max(0, batteryHealthPercent))
        self.cycleCount = max(0, cycleCount)
        self.voltageVolts = voltageVolts
        self.amperageAmps = amperageAmps
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
        self.isCharging = isCharging
        self.isExternalConnected = isExternalConnected
        self.isFullyCharged = isFullyCharged
        self.timeRemainingMinutes = timeRemainingMinutes
        self.isLowPowerMode = isLowPowerMode
        self.isDisplayAwake = isDisplayAwake
        self.timestamp = timestamp
    }

    public static let empty = BatteryHardwareSnapshot(
        hasBattery: false,
        chargePercent: 0,
        rawCurrentMah: 0,
        rawMaxMah: 0,
        nominalMaxMah: 0,
        designCapacityMah: 0,
        batteryHealthPercent: 0,
        cycleCount: 0,
        voltageVolts: 0,
        amperageAmps: 0,
        powerWatts: 0,
        temperatureCelsius: 0,
        isCharging: false,
        isExternalConnected: false,
        isFullyCharged: false,
        timeRemainingMinutes: nil,
        isLowPowerMode: false,
        isDisplayAwake: true,
        timestamp: Date()
    )
}

public struct AppEnergyMetadata: Codable, Equatable {
    public let id: String
    public let displayName: String
    public let bundlePath: String?
    public let bundleIdentifier: String?

    public init(id: String, displayName: String, bundlePath: String?, bundleIdentifier: String?) {
        self.id = id
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct ProcessKey: Hashable {
    public let pid: Int32
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

public struct ProcessEnergySnapshot: Equatable {
    public let pid: Int32
    public let startTime: UInt64
    public let energyNj: UInt64
    public let cpuTimeNs: UInt64
    public let wakeups: UInt64
    public let app: AppEnergyMetadata

    public init(
        pid: Int32,
        startTime: UInt64,
        energyNj: UInt64,
        cpuTimeNs: UInt64,
        wakeups: UInt64,
        app: AppEnergyMetadata
    ) {
        self.pid = pid
        self.startTime = startTime
        self.energyNj = energyNj
        self.cpuTimeNs = cpuTimeNs
        self.wakeups = wakeups
        self.app = app
    }

    public var key: ProcessKey {
        ProcessKey(pid: pid, startTime: startTime)
    }
}

public struct BatteryHistoryBucket: Codable, Equatable, Identifiable {
    public static let durationSeconds: Int64 = 900 // 15 minutes
    public static let maxAppsPerBucket = 32

    public var id: Int64 { bucketStartEpoch }
    public let bucketStartEpoch: Int64
    public var minChargePercent: Int
    public var maxChargePercent: Int
    public var lastChargePercent: Int
    public var wasCharging: Bool
    public var wasExternalConnected: Bool
    public var screenOnSeconds: Double
    public var averageDischargeWatts: Double?
    public var appEnergyNj: [String: UInt64]

    public var bucketStartDate: Date {
        Date(timeIntervalSince1970: TimeInterval(bucketStartEpoch))
    }

    public init(
        bucketStartEpoch: Int64,
        minChargePercent: Int,
        maxChargePercent: Int,
        lastChargePercent: Int,
        wasCharging: Bool,
        wasExternalConnected: Bool,
        screenOnSeconds: Double = 0,
        averageDischargeWatts: Double? = nil,
        appEnergyNj: [String: UInt64] = [:]
    ) {
        self.bucketStartEpoch = bucketStartEpoch
        self.minChargePercent = min(100, max(0, minChargePercent))
        self.maxChargePercent = min(100, max(0, maxChargePercent))
        self.lastChargePercent = min(100, max(0, lastChargePercent))
        self.wasCharging = wasCharging
        self.wasExternalConnected = wasExternalConnected
        self.screenOnSeconds = min(Double(Self.durationSeconds), max(0, screenOnSeconds))
        self.averageDischargeWatts = averageDischargeWatts
        self.appEnergyNj = Self.cappedAppMap(appEnergyNj)
    }

    public mutating func addAppEnergy(_ deltas: [String: UInt64]) {
        guard !deltas.isEmpty else { return }
        for (appID, delta) in deltas where delta > 0 {
            let existing = appEnergyNj[appID] ?? 0
            appEnergyNj[appID] = existing > UInt64.max - delta ? UInt64.max : existing + delta
        }
        if appEnergyNj.count > Self.maxAppsPerBucket {
            appEnergyNj = Self.cappedAppMap(appEnergyNj)
        }
    }

    public static func alignEpoch(_ date: Date) -> Int64 {
        let sec = Int64(floor(date.timeIntervalSince1970))
        let rem = sec >= 0 ? (sec % durationSeconds) : ((sec % durationSeconds) + durationSeconds) % durationSeconds
        return sec - rem
    }

    private static func cappedAppMap(_ map: [String: UInt64]) -> [String: UInt64] {
        guard map.count > maxAppsPerBucket else { return map }
        let top = map.sorted { $0.value > $1.value }.prefix(maxAppsPerBucket)
        var result: [String: UInt64] = [:]
        result.reserveCapacity(maxAppsPerBucket)
        for (k, v) in top { result[k] = v }
        return result
    }
}

public struct BatteryPersistedHistory: Codable, Equatable {
    public static let currentVersion = 1
    public static let maxBuckets = 96
    public static let maxMetadataEntries = 256

    public let version: Int
    public var recordingStartedAt: Date
    public var buckets: [BatteryHistoryBucket]
    public var appMetadata: [String: AppEnergyMetadata]

    public init(
        version: Int = currentVersion,
        recordingStartedAt: Date = Date(),
        buckets: [BatteryHistoryBucket] = [],
        appMetadata: [String: AppEnergyMetadata] = [:]
    ) {
        self.version = version
        self.recordingStartedAt = recordingStartedAt
        self.buckets = Array(buckets.sorted { $0.bucketStartEpoch < $1.bucketStartEpoch }.suffix(Self.maxBuckets))
        self.appMetadata = appMetadata
    }

    public mutating func prune(referenceDate: Date = Date()) {
        let cutoff = BatteryHistoryBucket.alignEpoch(referenceDate) - Int64(Self.maxBuckets - 1) * BatteryHistoryBucket.durationSeconds
        var byEpoch: [Int64: BatteryHistoryBucket] = [:]
        for bucket in buckets where bucket.bucketStartEpoch >= cutoff {
            byEpoch[bucket.bucketStartEpoch] = bucket
        }
        buckets = byEpoch.values.sorted { $0.bucketStartEpoch < $1.bucketStartEpoch }
        if buckets.count > Self.maxBuckets {
            buckets = Array(buckets.suffix(Self.maxBuckets))
        }

        if appMetadata.count > Self.maxMetadataEntries {
            let activeIDs = Set(buckets.flatMap { $0.appEnergyNj.keys })
            appMetadata = appMetadata.filter { activeIDs.contains($0.key) }
        }
    }
}

public struct AppEnergyEntry: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let bundlePath: String?
    public let energyWh: Double
    public let sharePercent: Double
    public let estimatedBatteryPercent: Double
    public let cpuSeconds: Double
    public let liveWatts: Double?
    public let isSignificant: Bool

    public init(
        id: String,
        displayName: String,
        bundlePath: String?,
        energyWh: Double,
        sharePercent: Double,
        estimatedBatteryPercent: Double,
        cpuSeconds: Double,
        liveWatts: Double?,
        isSignificant: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.energyWh = max(0, energyWh)
        self.sharePercent = min(100, max(0, sharePercent))
        self.estimatedBatteryPercent = max(0, estimatedBatteryPercent)
        self.cpuSeconds = max(0, cpuSeconds)
        self.liveWatts = liveWatts
        self.isSignificant = isSignificant
    }
}

public struct HourlyScreenUsageBar: Identifiable, Equatable {
    public var id: Int64 { Int64(hourStart.timeIntervalSince1970) }
    public let hourStart: Date
    public let minutes: Int
    public let isCurrentHour: Bool

    public init(hourStart: Date, minutes: Int, isCurrentHour: Bool) {
        self.hourStart = hourStart
        self.minutes = min(60, max(0, minutes))
        self.isCurrentHour = isCurrentHour
    }
}

// MARK: - App Identity Rollup

public enum AppEnergyAttribution {
    public static func resolveAppIdentity(
        executablePath: String?,
        bundlePath: String? = nil,
        bundleIdentifier: String? = nil,
        localizedName: String? = nil
    ) -> AppEnergyMetadata {
        if let candidate = bundlePath ?? executablePath,
           candidate.utf8.count <= 4096,
           let outerApp = outermostAppBundlePath(from: candidate) {
            let rawName = URL(fileURLWithPath: outerApp).deletingPathExtension().lastPathComponent
            let cleanName = rawName.isEmpty ? "App" : rawName
            // Prefer localizedName only when the input wasn't a nested sub-bundle inside an outer .app.
            let isOuterBundleDirectly = bundlePath != nil && outerApp == (bundlePath as NSString?)?.standardizingPath
            let name = (isOuterBundleDirectly ? localizedName : nil)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : cleanName
            return AppEnergyMetadata(
                id: "bundle:\(outerApp)",
                displayName: resolvedName,
                bundlePath: outerApp,
                bundleIdentifier: isOuterBundleDirectly ? bundleIdentifier : nil
            )
        }

        if let exe = executablePath, !exe.isEmpty, exe.utf8.count <= 4096 {
            let basename = URL(fileURLWithPath: exe).lastPathComponent
            let clean = basename.isEmpty ? "Process" : String(basename.prefix(128))
            return AppEnergyMetadata(
                id: "cmd:\(clean)",
                displayName: clean,
                bundlePath: nil,
                bundleIdentifier: nil
            )
        }

        return AppEnergyMetadata(id: "cmd:unknown", displayName: "Process", bundlePath: nil, bundleIdentifier: nil)
    }

    public static func outermostAppBundlePath(from path: String) -> String? {
        let components = (path as NSString).pathComponents
        var prefix = ""
        for component in components {
            if component == "/" {
                prefix = "/"
                continue
            }
            prefix = prefix.isEmpty ? component : (prefix == "/" ? "/\(component)" : "\(prefix)/\(component)")
            if component.lowercased().hasSuffix(".app"), component.count > 4 {
                return prefix
            }
        }
        return nil
    }
}

// MARK: - Process Energy Delta & Time-Range Aggregation

public enum AppEnergyAggregator {
    public static let nanojoulesPerWattHour: Double = 3_600_000_000_000.0
    public static let significantLiveWattsThreshold: Double = 2.0

    public struct DeltaResult {
        public let energyByApp: [String: UInt64]
        public let cpuByApp: [String: UInt64]
        public let metadata: [String: AppEnergyMetadata]
    }

    public static func computeDeltas(
        previous: [ProcessKey: ProcessEnergySnapshot],
        current: [ProcessKey: ProcessEnergySnapshot]
    ) -> DeltaResult {
        var energyByApp: [String: UInt64] = [:]
        var cpuByApp: [String: UInt64] = [:]
        var metadata: [String: AppEnergyMetadata] = [:]

        for (key, cur) in current {
            guard let prev = previous[key] else { continue }
            metadata[cur.app.id] = cur.app

            if cur.energyNj >= prev.energyNj {
                let dE = cur.energyNj - prev.energyNj
                if dE > 0 {
                    let old = energyByApp[cur.app.id] ?? 0
                    energyByApp[cur.app.id] = old > UInt64.max - dE ? UInt64.max : old + dE
                }
            }

            if cur.cpuTimeNs >= prev.cpuTimeNs {
                let dC = cur.cpuTimeNs - prev.cpuTimeNs
                if dC > 0 {
                    let old = cpuByApp[cur.app.id] ?? 0
                    cpuByApp[cur.app.id] = old > UInt64.max - dC ? UInt64.max : old + dC
                }
            }
        }

        return DeltaResult(energyByApp: energyByApp, cpuByApp: cpuByApp, metadata: metadata)
    }

    public static func aggregateBuckets(
        buckets: [BatteryHistoryBucket],
        metadata: [String: AppEnergyMetadata],
        range: BatteryTimeRange,
        selectedBucketEpoch: Int64?,
        liveWattsByApp: [String: Double],
        batteryCapacityWh: Double,
        now: Date
    ) -> [AppEnergyEntry] {
        let filtered: [BatteryHistoryBucket]
        if let selectedBucketEpoch {
            filtered = buckets.filter { $0.bucketStartEpoch == selectedBucketEpoch }
        } else {
            let lookbackSeconds: Int64
            switch range {
            case .oneHour: lookbackSeconds = 3_600
            case .sixHours: lookbackSeconds = 21_600
            case .twentyFourHours: lookbackSeconds = 86_400
            case .live, .sinceLaunch: lookbackSeconds = 86_400
            }
            let minEpoch = BatteryHistoryBucket.alignEpoch(now) - lookbackSeconds + BatteryHistoryBucket.durationSeconds
            filtered = buckets.filter { $0.bucketStartEpoch >= minEpoch }
        }

        var totals: [String: UInt64] = [:]
        for bucket in filtered {
            for (appID, nj) in bucket.appEnergyNj where nj > 0 {
                let old = totals[appID] ?? 0
                totals[appID] = old > UInt64.max - nj ? UInt64.max : old + nj
            }
        }

        return buildEntries(
            energyNjByApp: totals,
            cpuNsByApp: [:],
            liveWattsByApp: liveWattsByApp,
            metadata: metadata,
            batteryCapacityWh: batteryCapacityWh
        )
    }

    public static func aggregateSession(
        energyNjByApp: [String: UInt64],
        cpuNsByApp: [String: UInt64],
        liveWattsByApp: [String: Double],
        metadata: [String: AppEnergyMetadata],
        batteryCapacityWh: Double,
        isLiveMode: Bool
    ) -> [AppEnergyEntry] {
        if isLiveMode {
            let totalWatts = liveWattsByApp.values.reduce(0, +)
            let effectiveCapacityWh = max(10.0, batteryCapacityWh)
            return liveWattsByApp.compactMap { appID, watts in
                guard watts > 0.01 else { return nil }
                let meta = metadata[appID] ?? fallbackMetadata(appID: appID)
                let share = totalWatts > 0 ? (watts / totalWatts) * 100.0 : 0
                let estPctPerHour = (watts / effectiveCapacityWh) * 100.0
                return AppEnergyEntry(
                    id: appID,
                    displayName: meta.displayName,
                    bundlePath: meta.bundlePath,
                    energyWh: watts, // Live mode displays Watts primarily
                    sharePercent: share,
                    estimatedBatteryPercent: estPctPerHour,
                    cpuSeconds: Double(cpuNsByApp[appID] ?? 0) / 1_000_000_000.0,
                    liveWatts: watts,
                    isSignificant: watts >= significantLiveWattsThreshold || (watts >= 1.0 && share >= 35.0)
                )
            }
            .sorted { ($0.liveWatts ?? 0) > ($1.liveWatts ?? 0) }
        }

        return buildEntries(
            energyNjByApp: energyNjByApp,
            cpuNsByApp: cpuNsByApp,
            liveWattsByApp: liveWattsByApp,
            metadata: metadata,
            batteryCapacityWh: batteryCapacityWh
        )
    }

    private static func buildEntries(
        energyNjByApp: [String: UInt64],
        cpuNsByApp: [String: UInt64],
        liveWattsByApp: [String: Double],
        metadata: [String: AppEnergyMetadata],
        batteryCapacityWh: Double
    ) -> [AppEnergyEntry] {
        var totalWh = 0.0
        var whByApp: [(String, Double)] = []
        whByApp.reserveCapacity(energyNjByApp.count)

        for (appID, nj) in energyNjByApp where nj > 0 {
            let wh = Double(nj) / nanojoulesPerWattHour
            if wh.isFinite && wh > 0 {
                totalWh += wh
                whByApp.append((appID, wh))
            }
        }

        let effectiveCapacityWh = max(10.0, batteryCapacityWh)
        return whByApp
            .sorted { $0.1 > $1.1 }
            .compactMap { appID, wh in
                let meta = metadata[appID] ?? fallbackMetadata(appID: appID)
                let share = totalWh > 0 ? (wh / totalWh) * 100.0 : 0
                let estPct = (wh / effectiveCapacityWh) * 100.0
                let liveW = liveWattsByApp[appID]
                let significant = (liveW ?? 0) >= significantLiveWattsThreshold || (share >= 45.0 && wh >= 1.0)
                return AppEnergyEntry(
                    id: appID,
                    displayName: meta.displayName,
                    bundlePath: meta.bundlePath,
                    energyWh: wh,
                    sharePercent: share,
                    estimatedBatteryPercent: estPct,
                    cpuSeconds: Double(cpuNsByApp[appID] ?? 0) / 1_000_000_000.0,
                    liveWatts: liveW,
                    isSignificant: significant
                )
            }
    }

    private static func fallbackMetadata(appID: String) -> AppEnergyMetadata {
        if appID.hasPrefix("bundle:") {
            let path = String(appID.dropFirst("bundle:".count))
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return AppEnergyMetadata(id: appID, displayName: name.isEmpty ? "App" : name, bundlePath: path, bundleIdentifier: nil)
        }
        if appID.hasPrefix("cmd:") {
            return AppEnergyMetadata(id: appID, displayName: String(appID.dropFirst("cmd:".count)), bundlePath: nil, bundleIdentifier: nil)
        }
        return AppEnergyMetadata(id: appID, displayName: appID, bundlePath: nil, bundleIdentifier: nil)
    }

    public static func hourlyScreenUsage(
        buckets: [BatteryHistoryBucket],
        now: Date,
        calendar: Calendar = .current
    ) -> [HourlyScreenUsageBar] {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        guard let currentHourStart = calendar.date(from: comps) else { return [] }

        var secondsByHour: [Int64: Double] = [:]
        for bucket in buckets {
            let bucketDate = bucket.bucketStartDate
            let bComps = calendar.dateComponents([.year, .month, .day, .hour], from: bucketDate)
            if let hourDate = calendar.date(from: bComps) {
                let key = Int64(hourDate.timeIntervalSince1970)
                secondsByHour[key, default: 0] += bucket.screenOnSeconds
            }
        }

        var bars: [HourlyScreenUsageBar] = []
        bars.reserveCapacity(24)
        for offset in stride(from: -23, through: 0, by: 1) {
            guard let hourStart = calendar.date(byAdding: .hour, value: offset, to: currentHourStart) else { continue }
            let key = Int64(hourStart.timeIntervalSince1970)
            let secs = secondsByHour[key] ?? 0
            let mins = Int((secs / 60.0).rounded())
            bars.append(HourlyScreenUsageBar(hourStart: hourStart, minutes: mins, isCurrentHour: offset == 0))
        }
        return bars
    }
}

// MARK: - 24h pmset Log Bootstrap Parser

public enum BatteryLogParser {
    private static let maxLineLength = 4096

    private struct LogEvent {
        let timestamp: Date
        let chargePercent: Int?
        let isAC: Bool?
        let displayAwake: Bool?
    }

    public static func parsePmsetLog(_ text: String, now: Date) -> [BatteryHistoryBucket] {
        guard !text.isEmpty else { return [] }
        let alignedNowEpoch = BatteryHistoryBucket.alignEpoch(now)
        let firstBucketEpoch = alignedNowEpoch - Int64(BatteryPersistedHistory.maxBuckets - 1) * BatteryHistoryBucket.durationSeconds
        let windowStart = Date(timeIntervalSince1970: TimeInterval(firstBucketEpoch))
        let lookbackCutoff = windowStart.addingTimeInterval(-3600)

        var events: [LogEvent] = []
        text.enumerateLines { line, _ in
            guard line.count >= 26, line.count <= maxLineLength else { return }
            let utf8 = Array(line.utf8)
            // Quick digit check for YYYY-MM-DD HH:MM:SS
            guard utf8[0] >= 48, utf8[0] <= 57, utf8[4] == 45, utf8[7] == 45 else { return }

            let hasPowerTag = line.contains("Using AC") || line.contains("Using Batt") || line.contains("Using BATT") || line.contains("Charge:")
            let hasDisplayOn = line.contains("Display is turned on")
            let hasDisplayOff = line.contains("Display is turned off") || line.contains("Entering Sleep")
            let hasFullWake = line.contains("Wake from") || line.contains("DarkWake to FullWake")
            guard hasPowerTag || hasDisplayOn || hasDisplayOff || hasFullWake else { return }

            guard let timestamp = parseTimestamp(utf8),
                  timestamp >= lookbackCutoff,
                  timestamp <= now else { return }

            let isAC: Bool?
            if line.contains("Using AC") {
                isAC = true
            } else if line.contains("Using Batt") || line.contains("Using BATT") {
                isAC = false
            } else {
                isAC = nil
            }

            let charge = parseCharge(in: line)

            let displayAwake: Bool?
            if hasDisplayOn || hasFullWake {
                displayAwake = true
            } else if hasDisplayOff {
                displayAwake = false
            } else {
                displayAwake = nil
            }

            events.append(LogEvent(timestamp: timestamp, chargePercent: charge, isAC: isAC, displayAwake: displayAwake))
        }

        guard !events.isEmpty else { return [] }
        events.sort { $0.timestamp < $1.timestamp }

        // Prepare 96 buckets covering [firstBucketEpoch, alignedNowEpoch]
        var result: [BatteryHistoryBucket] = []
        result.reserveCapacity(BatteryPersistedHistory.maxBuckets)

        var currentCharge: Int?
        var currentAC = false
        var currentDisplayAwake = false
        var eventIndex = 0

        // Seed state from events strictly before windowStart
        while eventIndex < events.count && events[eventIndex].timestamp < windowStart {
            let ev = events[eventIndex]
            if let c = ev.chargePercent { currentCharge = c }
            if let ac = ev.isAC { currentAC = ac }
            if let d = ev.displayAwake { currentDisplayAwake = d }
            eventIndex += 1
        }

        for slotIndex in 0..<BatteryPersistedHistory.maxBuckets {
            let slotStartEpoch = firstBucketEpoch + Int64(slotIndex) * BatteryHistoryBucket.durationSeconds
            let slotStart = Date(timeIntervalSince1970: TimeInterval(slotStartEpoch))
            let slotEnd = Date(timeIntervalSince1970: TimeInterval(slotStartEpoch + BatteryHistoryBucket.durationSeconds))
            let clampedSlotEnd = min(slotEnd, now)

            var hadChargeIncrease = false
            // Apply events at exact slotStart boundary before seeding the slot's starting state.
            while eventIndex < events.count && events[eventIndex].timestamp <= slotStart {
                let ev = events[eventIndex]
                if let newCharge = ev.chargePercent {
                    if let prev = currentCharge, newCharge > prev {
                        hadChargeIncrease = true
                    }
                    currentCharge = newCharge
                }
                if let ac = ev.isAC { currentAC = ac }
                if let d = ev.displayAwake { currentDisplayAwake = d }
                eventIndex += 1
            }

            var bucketMin: Int? = currentCharge
            var bucketMax: Int? = currentCharge
            var bucketLast: Int? = currentCharge
            var hadAC = currentAC
            var screenOnSecs: Double = 0
            var cursor = slotStart
            var awakeNow = currentDisplayAwake

            while eventIndex < events.count && events[eventIndex].timestamp < slotEnd {
                let ev = events[eventIndex]
                if awakeNow && ev.timestamp > cursor {
                    screenOnSecs += min(ev.timestamp, clampedSlotEnd).timeIntervalSince(cursor)
                }
                cursor = max(cursor, min(ev.timestamp, clampedSlotEnd))

                if let newCharge = ev.chargePercent {
                    if let prev = currentCharge, newCharge > prev {
                        hadChargeIncrease = true
                    }
                    currentCharge = newCharge
                    bucketMin = bucketMin.map { min($0, newCharge) } ?? newCharge
                    bucketMax = bucketMax.map { max($0, newCharge) } ?? newCharge
                    bucketLast = newCharge
                }
                if let ac = ev.isAC {
                    currentAC = ac
                    if ac { hadAC = true }
                }
                if let d = ev.displayAwake {
                    awakeNow = d
                    currentDisplayAwake = d
                }
                eventIndex += 1
            }

            if awakeNow && clampedSlotEnd > cursor {
                screenOnSecs += clampedSlotEnd.timeIntervalSince(cursor)
            }

            if let minC = bucketMin, let maxC = bucketMax, let lastC = bucketLast {
                let isCharging = hadAC && (hadChargeIncrease || lastC < 100)
                result.append(BatteryHistoryBucket(
                    bucketStartEpoch: slotStartEpoch,
                    minChargePercent: minC,
                    maxChargePercent: maxC,
                    lastChargePercent: lastC,
                    wasCharging: isCharging,
                    wasExternalConnected: hadAC,
                    screenOnSeconds: screenOnSecs,
                    averageDischargeWatts: nil,
                    appEnergyNj: [:]
                ))
            }
        }

        return result
    }

    private static func parseCharge(in line: String) -> Int? {
        guard let range = line.range(of: "Charge:") else { return nil }
        var idx = range.upperBound
        while idx < line.endIndex && line[idx] == " " {
            idx = line.index(after: idx)
        }
        var value = 0
        var digits = 0
        while idx < line.endIndex, let d = line[idx].asciiValue, d >= 48, d <= 57, digits < 4 {
            value = value * 10 + Int(d - 48)
            digits += 1
            idx = line.index(after: idx)
        }
        guard digits > 0, value >= 0, value <= 100 else { return nil }
        return value
    }

    // Parses "YYYY-MM-DD HH:MM:SS +HHMM" in pure ASCII with zero heap formatter overhead.
    private static func parseTimestamp(_ bytes: [UInt8]) -> Date? {
        guard bytes.count >= 25 else { return nil }
        func num(_ start: Int, _ len: Int) -> Int? {
            var v = 0
            for i in start..<(start + len) {
                let b = bytes[i]
                guard b >= 48, b <= 57 else { return nil }
                v = v * 10 + Int(b - 48)
            }
            return v
        }
        guard bytes[4] == 45, bytes[7] == 45, bytes[10] == 32, bytes[13] == 58, bytes[16] == 58, bytes[19] == 32 else {
            return nil
        }
        let signByte = bytes[20]
        guard signByte == 43 || signByte == 45 else { return nil }
        guard let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2),
              let tzHour = num(21, 2), let tzMin = num(23, 2),
              (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            return nil
        }
        var tmVal = tm()
        tmVal.tm_year = Int32(year - 1900)
        tmVal.tm_mon = Int32(month - 1)
        tmVal.tm_mday = Int32(day)
        tmVal.tm_hour = Int32(hour)
        tmVal.tm_min = Int32(minute)
        tmVal.tm_sec = Int32(second)
        let utcSeconds = timegm(&tmVal)
        guard utcSeconds != -1 else { return nil }
        let offsetSeconds = (signByte == 43 ? 1 : -1) * (tzHour * 3600 + tzMin * 60)
        return Date(timeIntervalSince1970: TimeInterval(utcSeconds - offsetSeconds))
    }
}

// MARK: - Fail-Closed Encrypted-Free Descriptor-Safe History Persistence

public final class BatteryHistoryStore {
    public static let maxFileBytes = 2 * 1_048_576
    private static let fileName = "history_v1.json"

    private let baseURL: URL

    public init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.baseURL = appSupport
        }
    }

    private func openDirectory(create: Bool) throws -> SecureDirectory {
        let root = try SecureDirectory.boundaryRoot(baseURL)
        let appDir = try root.child("Yeoman", create: create)
        return try appDir.child("battery_history", create: create)
    }

    public func load() throws -> BatteryPersistedHistory? {
        let dir = try openDirectory(create: false)
        guard try dir.exists(Self.fileName) else { return nil }
        let data = try dir.read(Self.fileName, limit: Self.maxFileBytes)
        let decoded = try JSONDecoder().decode(BatteryPersistedHistory.self, from: data)
        guard decoded.version == BatteryPersistedHistory.currentVersion else {
            throw SecurityFailure.rejected("Nicht unterstützte Batterie-Verlaufsversion.")
        }
        return decoded
    }

    public func save(_ history: BatteryPersistedHistory) throws {
        var copy = history
        copy.prune()
        let data = try JSONEncoder().encode(copy)
        guard data.count <= Self.maxFileBytes else {
            throw SecurityFailure.rejected("Batterie-Verlauf überschreitet die maximale Dateigröße.")
        }
        let dir = try openDirectory(create: true)
        try dir.write(data, name: Self.fileName)
    }

    public func clear() throws {
        let dir = try openDirectory(create: false)
        try dir.remove(Self.fileName)
    }
}
