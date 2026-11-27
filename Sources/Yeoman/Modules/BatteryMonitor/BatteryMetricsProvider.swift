import AppKit
import Combine
import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.ps

public final class BatteryMetricsProvider: ObservableObject {
    public static let shared = BatteryMetricsProvider()

    @Published public private(set) var hardware: BatteryHardwareSnapshot = .empty
    @Published public private(set) var buckets: [BatteryHistoryBucket] = []
    @Published public private(set) var hourlyScreenUsage: [HourlyScreenUsageBar] = []
    @Published public private(set) var liveEntries: [AppEnergyEntry] = []
    @Published public private(set) var oneHourEntries: [AppEnergyEntry] = []
    @Published public private(set) var sixHourEntries: [AppEnergyEntry] = []
    @Published public private(set) var twentyFourHourEntries: [AppEnergyEntry] = []
    @Published public private(set) var sessionEntries: [AppEnergyEntry] = []
    @Published public private(set) var selectedBucketEntries: [AppEnergyEntry] = []
    @Published public private(set) var selectedBucketEpoch: Int64? = nil
    @Published public private(set) var recordingStartedAt: Date = Date()
    @Published public private(set) var isBootstrappingHistory: Bool = false

    private let queue = DispatchQueue(label: "de.trst.yeoman.battery.sampler", qos: .utility)
    private let store: BatteryHistoryStore
    private let runPmsetLog: () throws -> String

    // State confined exclusively to `queue`.
    private var generation: UInt64 = 0
    private var isRunning = false
    private var isLivePolling = false
    private var bootstrapAttempted = false
    private var backgroundTimer: DispatchSourceTimer?
    private var liveTimer: DispatchSourceTimer?

    private var history = BatteryPersistedHistory()
    private var previousBackgroundSample: [ProcessKey: ProcessEnergySnapshot] = [:]
    private var lastBackgroundSampleDate: Date?
    private var previousLiveSample: [ProcessKey: ProcessEnergySnapshot] = [:]
    private var lastLiveSampleDate: Date?
    private var lastPersistDate: Date = .distantPast

    private var sessionEnergyNjByApp: [String: UInt64] = [:]
    private var sessionCpuNsByApp: [String: UInt64] = [:]
    private var liveWattsByApp: [String: Double] = [:]
    private var activeSelectedBucketEpoch: Int64?

    private var workspaceObserver: NSObjectProtocol?
    private var powerStateObserver: NSObjectProtocol?

    public init(
        store: BatteryHistoryStore = BatteryHistoryStore(),
        runPmsetLog: @escaping () throws -> String = {
            let result = try BoundedProcess.runTail("/usr/bin/pmset", ["-g", "log"], timeout: 8)
            return String(data: result.data, encoding: .utf8) ?? ""
        }
    ) {
        self.store = store
        self.runPmsetLog = runPmsetLog
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    public static func hardwareHasBattery() -> Bool {
        readBatteryHardware().hasBattery
    }

    public func start() {
        let initialSnapshot = Self.readBatteryHardware()
        publishHardware(initialSnapshot)

        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunning else { return }
            self.isRunning = true
            self.generation &+= 1
            let activeGen = self.generation

            if let loaded = try? self.store.load() {
                self.history = loaded
                self.history.prune()
            } else {
                self.history = BatteryPersistedHistory()
            }

            let now = Date()
            self.recordBatterySnapshotLocked(initialSnapshot, screenElapsedSeconds: 0, appDeltas: [:], now: now)
            let baseline = Self.sampleProcesses()
            self.previousBackgroundSample = baseline
            self.lastBackgroundSampleDate = now
            self.previousLiveSample = baseline
            self.lastLiveSampleDate = now

            self.publishStateLocked(now: now)
            self.startBackgroundTimerLocked(generation: activeGen)
            self.registerNotifications()

            if !self.bootstrapAttempted {
                self.bootstrapAttempted = true
                self.runBootstrapLocked(generation: activeGen)
            }
        }
    }

    public func stop() {
        unregisterNotifications()
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.isLivePolling = false
            self.generation &+= 1
            self.backgroundTimer?.cancel()
            self.backgroundTimer = nil
            self.liveTimer?.cancel()
            self.liveTimer = nil
            try? self.store.save(self.history)
        }
    }

    public func startLivePolling() {
        queue.async { [weak self] in
            guard let self else { return }
            let activeGen = self.generation
            guard !self.isLivePolling else {
                self.sampleLiveStepLocked(generation: activeGen)
                return
            }
            self.isLivePolling = true
            self.sampleLiveStepLocked(generation: activeGen)

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1.2, repeating: 2.5)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.sampleLiveStepLocked(generation: activeGen)
            }
            self.liveTimer?.cancel()
            self.liveTimer = timer
            timer.resume()
        }
    }

    public func stopLivePolling() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isLivePolling = false
            self.liveTimer?.cancel()
            self.liveTimer = nil
        }
    }

    public func refreshNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.sampleBackgroundStepLocked(generation: self.generation, forcePersist: true)
        }
    }

    public func selectBucket(_ epoch: Int64?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeSelectedBucketEpoch = epoch
            self.publishStateLocked(now: Date())
        }
    }

    public func clearHistory() {
        queue.async { [weak self] in
            guard let self else { return }
            self.history = BatteryPersistedHistory()
            self.sessionEnergyNjByApp.removeAll()
            self.sessionCpuNsByApp.removeAll()
            self.liveWattsByApp.removeAll()
            self.activeSelectedBucketEpoch = nil
            try? self.store.clear()
            let hw = Self.readBatteryHardware()
            self.recordBatterySnapshotLocked(hw, screenElapsedSeconds: 0, appDeltas: [:], now: Date())
            self.publishHardware(hw)
            self.publishStateLocked(now: Date())
        }
    }

    public func entries(for range: BatteryTimeRange) -> [AppEnergyEntry] {
        if selectedBucketEpoch != nil, range == .oneHour || range == .sixHours || range == .twentyFourHours {
            return selectedBucketEntries
        }
        switch range {
        case .live: return liveEntries
        case .oneHour: return oneHourEntries
        case .sixHours: return sixHourEntries
        case .twentyFourHours: return twentyFourHourEntries
        case .sinceLaunch: return sessionEntries
        }
    }

    // MARK: - Notifications

    private func registerNotifications() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.unregisterNotifications()
            self.workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshNow()
            }
            self.powerStateObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshNow()
            }
        }
    }

    private func unregisterNotifications() {
        let wsObs = workspaceObserver
        let pwrObs = powerStateObserver
        workspaceObserver = nil
        powerStateObserver = nil
        if let wsObs {
            NSWorkspace.shared.notificationCenter.removeObserver(wsObs)
        }
        if let pwrObs {
            NotificationCenter.default.removeObserver(pwrObs)
        }
    }

    // MARK: - Background & Live Sampling (Serial Queue Only)

    private func startBackgroundTimerLocked(generation: UInt64) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 30.0)
        timer.setEventHandler { [weak self] in
            self?.sampleBackgroundStepLocked(generation: generation, forcePersist: false)
        }
        backgroundTimer?.cancel()
        backgroundTimer = timer
        timer.resume()
    }

    private func sampleBackgroundStepLocked(generation: UInt64, forcePersist: Bool) {
        guard isRunning, self.generation == generation else { return }
        let now = Date()
        let hw = Self.readBatteryHardware()
        let currentProcs = Self.sampleProcesses()
        let deltas = AppEnergyAggregator.computeDeltas(previous: previousBackgroundSample, current: currentProcs)

        let rawElapsed = lastBackgroundSampleDate.map { now.timeIntervalSince($0) } ?? 0
        // Cap delta after sleep/wake so a 6h lid-close doesn't falsely credit screen-on minutes.
        let boundedElapsed = min(max(0, rawElapsed), 90.0)
        let screenDelta = hw.isDisplayAwake ? boundedElapsed : 0

        for (appID, dE) in deltas.energyByApp {
            let old = sessionEnergyNjByApp[appID] ?? 0
            sessionEnergyNjByApp[appID] = old > UInt64.max - dE ? UInt64.max : old + dE
        }
        for (appID, dC) in deltas.cpuByApp {
            let old = sessionCpuNsByApp[appID] ?? 0
            sessionCpuNsByApp[appID] = old > UInt64.max - dC ? UInt64.max : old + dC
        }
        for (appID, meta) in deltas.metadata {
            history.appMetadata[appID] = meta
        }

        recordBatterySnapshotLocked(hw, screenElapsedSeconds: screenDelta, appDeltas: deltas.energyByApp, now: now)
        previousBackgroundSample = currentProcs
        lastBackgroundSampleDate = now

        if forcePersist || now.timeIntervalSince(lastPersistDate) >= 120.0 {
            lastPersistDate = now
            try? store.save(history)
        }

        publishHardware(hw)
        publishStateLocked(now: now)
    }

    private func sampleLiveStepLocked(generation: UInt64) {
        guard isRunning, self.generation == generation, isLivePolling else { return }
        let now = Date()
        let hw = Self.readBatteryHardware()
        let currentProcs = Self.sampleProcesses()

        let elapsed = lastLiveSampleDate.map { now.timeIntervalSince($0) } ?? 0
        if !previousLiveSample.isEmpty && elapsed >= 0.4 && elapsed <= 30.0 {
            let deltas = AppEnergyAggregator.computeDeltas(previous: previousLiveSample, current: currentProcs)
            var newWatts: [String: Double] = [:]
            for (appID, nj) in deltas.energyByApp where nj > 0 {
                let watts = (Double(nj) / 1_000_000_000.0) / elapsed
                if watts.isFinite && watts > 0.005 {
                    newWatts[appID] = watts
                }
            }
            for (appID, meta) in deltas.metadata {
                history.appMetadata[appID] = meta
            }
            liveWattsByApp = newWatts
        }

        previousLiveSample = currentProcs
        lastLiveSampleDate = now

        publishHardware(hw)
        publishStateLocked(now: now)
    }

    private func recordBatterySnapshotLocked(
        _ hw: BatteryHardwareSnapshot,
        screenElapsedSeconds: Double,
        appDeltas: [String: UInt64],
        now: Date
    ) {
        guard hw.hasBattery else { return }
        let epoch = BatteryHistoryBucket.alignEpoch(now)
        if let idx = history.buckets.firstIndex(where: { $0.bucketStartEpoch == epoch }) {
            var bucket = history.buckets[idx]
            bucket.minChargePercent = min(bucket.minChargePercent, hw.chargePercent)
            bucket.maxChargePercent = max(bucket.maxChargePercent, hw.chargePercent)
            bucket.lastChargePercent = hw.chargePercent
            bucket.wasCharging = bucket.wasCharging || hw.isCharging
            bucket.wasExternalConnected = bucket.wasExternalConnected || hw.isExternalConnected
            bucket.screenOnSeconds = min(Double(BatteryHistoryBucket.durationSeconds), bucket.screenOnSeconds + max(0, screenElapsedSeconds))
            if hw.powerWatts < -0.1 {
                let absW = abs(hw.powerWatts)
                if let prevAvg = bucket.averageDischargeWatts {
                    bucket.averageDischargeWatts = (prevAvg * 0.8) + (absW * 0.2)
                } else {
                    bucket.averageDischargeWatts = absW
                }
            }
            bucket.addAppEnergy(appDeltas)
            history.buckets[idx] = bucket
        } else {
            var bucket = BatteryHistoryBucket(
                bucketStartEpoch: epoch,
                minChargePercent: hw.chargePercent,
                maxChargePercent: hw.chargePercent,
                lastChargePercent: hw.chargePercent,
                wasCharging: hw.isCharging,
                wasExternalConnected: hw.isExternalConnected,
                screenOnSeconds: max(0, screenElapsedSeconds),
                averageDischargeWatts: hw.powerWatts < -0.1 ? abs(hw.powerWatts) : nil,
                appEnergyNj: appDeltas
            )
            bucket.addAppEnergy([:])
            history.buckets.append(bucket)
        }
        history.prune(referenceDate: now)
    }

    private func runBootstrapLocked(generation: UInt64) {
        DispatchQueue.main.async { [weak self] in
            self?.isBootstrappingHistory = true
        }
        let logLoader = runPmsetLog
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let logText = (try? logLoader()) ?? ""
            let parsedBuckets = BatteryLogParser.parsePmsetLog(logText, now: Date())
            self?.queue.async { [weak self] in
                guard let self, self.isRunning, self.generation == generation else {
                    DispatchQueue.main.async { self?.isBootstrappingHistory = false }
                    return
                }
                if !parsedBuckets.isEmpty {
                    self.mergeBootstrapBucketsLocked(parsedBuckets)
                    try? self.store.save(self.history)
                    self.publishStateLocked(now: Date())
                }
                DispatchQueue.main.async { [weak self] in
                    self?.isBootstrappingHistory = false
                }
            }
        }
    }

    private func mergeBootstrapBucketsLocked(_ parsed: [BatteryHistoryBucket]) {
        var byEpoch: [Int64: BatteryHistoryBucket] = [:]
        for existing in history.buckets {
            byEpoch[existing.bucketStartEpoch] = existing
        }
        for boot in parsed {
            if var existing = byEpoch[boot.bucketStartEpoch] {
                existing.minChargePercent = min(existing.minChargePercent, boot.minChargePercent)
                existing.maxChargePercent = max(existing.maxChargePercent, boot.maxChargePercent)
                existing.wasCharging = existing.wasCharging || boot.wasCharging
                existing.wasExternalConnected = existing.wasExternalConnected || boot.wasExternalConnected
                existing.screenOnSeconds = max(existing.screenOnSeconds, boot.screenOnSeconds)
                byEpoch[boot.bucketStartEpoch] = existing
            } else {
                byEpoch[boot.bucketStartEpoch] = boot
            }
        }
        history.buckets = byEpoch.values.sorted { $0.bucketStartEpoch < $1.bucketStartEpoch }
        history.prune()
    }

    private func publishHardware(_ hw: BatteryHardwareSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.hardware = hw
        }
    }

    private func publishStateLocked(now: Date) {
        let hw = Self.readBatteryHardware()
        let capacityWh: Double
        if hw.hasBattery {
            let capMah = Double(hw.nominalMaxMah > 0 ? hw.nominalMaxMah : max(hw.rawMaxMah, 4000))
            let volts = hw.voltageVolts > 5.0 ? hw.voltageVolts : 11.4
            capacityWh = (capMah * volts) / 1000.0
        } else {
            capacityWh = 65.0
        }

        let bucketsCopy = history.buckets
        let metaCopy = history.appMetadata
        let hourly = AppEnergyAggregator.hourlyScreenUsage(buckets: bucketsCopy, now: now)
        let live = AppEnergyAggregator.aggregateSession(
            energyNjByApp: sessionEnergyNjByApp,
            cpuNsByApp: sessionCpuNsByApp,
            liveWattsByApp: liveWattsByApp,
            metadata: metaCopy,
            batteryCapacityWh: capacityWh,
            isLiveMode: true
        )
        let h1 = AppEnergyAggregator.aggregateBuckets(
            buckets: bucketsCopy,
            metadata: metaCopy,
            range: .oneHour,
            selectedBucketEpoch: nil,
            liveWattsByApp: liveWattsByApp,
            batteryCapacityWh: capacityWh,
            now: now
        )
        let h6 = AppEnergyAggregator.aggregateBuckets(
            buckets: bucketsCopy,
            metadata: metaCopy,
            range: .sixHours,
            selectedBucketEpoch: nil,
            liveWattsByApp: liveWattsByApp,
            batteryCapacityWh: capacityWh,
            now: now
        )
        let h24 = AppEnergyAggregator.aggregateBuckets(
            buckets: bucketsCopy,
            metadata: metaCopy,
            range: .twentyFourHours,
            selectedBucketEpoch: nil,
            liveWattsByApp: liveWattsByApp,
            batteryCapacityWh: capacityWh,
            now: now
        )
        let session = AppEnergyAggregator.aggregateSession(
            energyNjByApp: sessionEnergyNjByApp,
            cpuNsByApp: sessionCpuNsByApp,
            liveWattsByApp: liveWattsByApp,
            metadata: metaCopy,
            batteryCapacityWh: capacityWh,
            isLiveMode: false
        )
        let bucketFilter = activeSelectedBucketEpoch.map { epoch in
            AppEnergyAggregator.aggregateBuckets(
                buckets: bucketsCopy,
                metadata: metaCopy,
                range: .twentyFourHours,
                selectedBucketEpoch: epoch,
                liveWattsByApp: liveWattsByApp,
                batteryCapacityWh: capacityWh,
                now: now
            )
        } ?? []
        let startedAt = history.recordingStartedAt
        let activeBucket = activeSelectedBucketEpoch

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.buckets = bucketsCopy
            self.hourlyScreenUsage = hourly
            self.liveEntries = live
            self.oneHourEntries = h1
            self.sixHourEntries = h6
            self.twentyFourHourEntries = h24
            self.sessionEntries = session
            self.selectedBucketEntries = bucketFilter
            self.selectedBucketEpoch = activeBucket
            self.recordingStartedAt = startedAt
        }
    }

    // MARK: - Low-Level IOKit & Kernel Samplers

    public static func readBatteryHardware() -> BatteryHardwareSnapshot {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return .empty }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
            return .empty
        }

        let installed = (dict["BatteryInstalled"] as? Bool) ?? ((dict["BatteryInstalled"] as? Int) != 0)
        let currentCap = intValue(dict["CurrentCapacity"]) ?? 0
        let maxCap = intValue(dict["MaxCapacity"]) ?? 100
        let chargePercent = maxCap > 0 ? Int((Double(currentCap) / Double(maxCap) * 100.0).rounded()) : currentCap

        let rawCurrent = intValue(dict["AppleRawCurrentCapacity"]) ?? 0
        let rawMax = intValue(dict["AppleRawMaxCapacity"]) ?? 0
        let nominalMax = intValue(dict["NominalChargeCapacity"]) ?? rawMax
        let designCap = intValue(dict["DesignCapacity"]) ?? nominalMax
        let healthNumerator = nominalMax > 0 ? nominalMax : rawMax
        let healthPercent = designCap > 0 ? (Double(healthNumerator) / Double(designCap)) * 100.0 : 100.0

        let cycles = intValue(dict["CycleCount"]) ?? 0
        let voltageMv = intValue(dict["Voltage"]) ?? 0
        let voltageVolts = Double(voltageMv) / 1000.0
        let rawAmpsMa = intValue(dict["InstantAmperage"]) ?? intValue(dict["Amperage"]) ?? 0
        let amperageAmps = Double(rawAmpsMa) / 1000.0
        let powerWatts = voltageVolts * amperageAmps
        let rawTemp = intValue(dict["Temperature"]) ?? 0
        let tempC = Double(rawTemp) / 100.0

        let isCharging = boolValue(dict["IsCharging"]) ?? false
        let external = boolValue(dict["ExternalConnected"]) ?? false
        let full = boolValue(dict["FullyCharged"]) ?? false

        let rawRemaining: Int?
        if isCharging {
            rawRemaining = intValue(dict["AvgTimeToFull"]) ?? intValue(dict["TimeRemaining"])
        } else {
            rawRemaining = intValue(dict["TimeRemaining"]) ?? intValue(dict["AvgTimeToEmpty"])
        }
        let timeRemaining: Int? = if let mins = rawRemaining, mins > 0, mins < 6000 { mins } else { nil }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0

        return BatteryHardwareSnapshot(
            hasBattery: installed || designCap > 0 || maxCap > 0,
            chargePercent: chargePercent,
            rawCurrentMah: rawCurrent,
            rawMaxMah: rawMax,
            nominalMaxMah: nominalMax,
            designCapacityMah: designCap,
            batteryHealthPercent: healthPercent,
            cycleCount: cycles,
            voltageVolts: voltageVolts,
            amperageAmps: amperageAmps,
            powerWatts: powerWatts,
            temperatureCelsius: tempC,
            isCharging: isCharging,
            isExternalConnected: external,
            isFullyCharged: full,
            timeRemainingMinutes: timeRemaining,
            isLowPowerMode: lowPower,
            isDisplayAwake: displayAwake,
            timestamp: Date()
        )
    }

    public static func sampleProcesses() -> [ProcessKey: ProcessEnergySnapshot] {
        let maxPids = 8192
        var pids = [pid_t](repeating: 0, count: maxPids)
        let bufferBytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let bytesWritten = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferBytes)
        guard bytesWritten > 0 else { return [:] }

        let count = min(pids.count, Int(bytesWritten) / MemoryLayout<pid_t>.stride)
        var result: [ProcessKey: ProcessEnergySnapshot] = [:]
        result.reserveCapacity(min(count, 512))
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 1 else { continue }

            var rinfo = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &rinfo) { ptr -> Int32 in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: rusage_info_t?.self)
                return proc_pid_rusage(pid, RUSAGE_INFO_V6, raw)
            }
            guard status == 0 else { continue }
            guard rinfo.ri_energy_nj > 0 || rinfo.ri_user_time > 0 || rinfo.ri_system_time > 0 else { continue }

            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let exePath = pathLength > 0 ? String(cString: pathBuffer) : nil
            let identity = AppEnergyAttribution.resolveAppIdentity(executablePath: exePath)

            let cpuNs = rinfo.ri_user_time &+ rinfo.ri_system_time
            let snap = ProcessEnergySnapshot(
                pid: pid,
                startTime: rinfo.ri_proc_start_abstime,
                energyNj: rinfo.ri_energy_nj,
                cpuTimeNs: cpuNs,
                wakeups: rinfo.ri_pkg_idle_wkups,
                app: identity
            )
            result[snap.key] = snap
        }

        return result
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber {
            let val = n.int64Value
            return Int(exactly: val)
        }
        return raw as? Int
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }
}
