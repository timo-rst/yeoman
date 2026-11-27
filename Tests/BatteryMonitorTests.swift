import Darwin
import Foundation
import YeomanCore

func runBatteryMonitorTests() {
    let harness = TestHarness.shared

    harness.runSuite("Battery Monitor: BoundedProcess.runTail") {
        harness.test("runTail preserves trailing bytes when stdout exceeds tailLimit") {
            let output = try BoundedProcess.runTail(
                "/usr/bin/python3",
                ["-c", "import sys; sys.stdout.write('A' * 35000 + 'TAIL_MARKER_END')"],
                timeout: 5,
                tailLimit: 4096,
                totalReadLimit: 100_000
            )
            assertEqual(output.status, 0)
            assertEqual(output.data.count, 4096)
            let text = String(data: output.data, encoding: .utf8) ?? ""
            assertTrue(text.hasSuffix("TAIL_MARKER_END"), "Expected trailing marker in runTail output")
        }

        harness.test("runTail rejects output exceeding totalReadLimit") {
            var didThrow = false
            do {
                _ = try BoundedProcess.runTail(
                    "/usr/bin/python3",
                    ["-c", "import sys; sys.stdout.write('B' * 30000)"],
                    timeout: 5,
                    tailLimit: 1024,
                    totalReadLimit: 8192
                )
            } catch {
                didThrow = true
            }
            assertTrue(didThrow, "Expected runTail to reject output above totalReadLimit")
        }

        harness.test("runTail drains stderr concurrently without corrupting stdout tail") {
            let output = try BoundedProcess.runTail(
                "/usr/bin/python3",
                ["-c", "import sys; sys.stderr.write('E' * 12000); sys.stderr.flush(); sys.stdout.write('OK')"],
                timeout: 5,
                tailLimit: 4096,
                totalReadLimit: 65536
            )
            assertEqual(output.status, 0)
            assertEqual(String(data: output.data, encoding: .utf8), "OK")
        }
    }

    harness.runSuite("Battery Monitor: Attribution, Log Parser & Aggregation") {
        harness.test("outermost app bundle rollup groups nested Chromium/Electron helpers cleanly") {
            let helperExe = "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/158.1/Helpers/Brave Browser Helper (Renderer).app/Contents/MacOS/Brave Browser Helper (Renderer)"
            let resolved = AppEnergyAttribution.resolveAppIdentity(executablePath: helperExe)
            assertEqual(resolved.id, "bundle:/Applications/Brave Browser.app")
            assertEqual(resolved.displayName, "Brave Browser")
            assertEqual(resolved.bundlePath, "/Applications/Brave Browser.app")

            let directExe = "/Applications/melonDS.app/Contents/MacOS/melonDS"
            let melon = AppEnergyAttribution.resolveAppIdentity(executablePath: directExe)
            assertEqual(melon.id, "bundle:/Applications/melonDS.app")
            assertEqual(melon.displayName, "melonDS")

            let cliExe = "/usr/local/bin/ffmpeg"
            let cli = AppEnergyAttribution.resolveAppIdentity(executablePath: cliExe)
            assertEqual(cli.id, "cmd:ffmpeg")
            assertEqual(cli.displayName, "ffmpeg")
            assertNil(cli.bundlePath)
        }

        harness.test("parsePmsetLog extracts 24h charge bars, AC spans, and screen-on minutes across midnight") {
            let fmt = ISO8601DateFormatter()
            let now = fmt.date(from: "2026-11-27T10:00:00+01:00")!
            let oversized = String(repeating: "X", count: 5000)
            let log = """
            2026-11-26 22:00:00 +0100 Assertions          Summary Using Batt(Charge: 25)
            2026-11-26 23:30:00 +0100 Assertions          Summary Using AC (Charge:18%)
            2026-11-26 23:45:00 +0100 Notification        Display is turned off
            2026-11-27 00:30:00 +0100 Sleep               Entering Sleep state Using AC (Charge:64%)
            2026-11-27 08:00:00 +0100 Wake                Wake from Deep Idle Using BATT (Charge:95%)
            2026-11-27 08:00:00 +0100 Notification        Display is turned on
            2026-11-27 08:30:00 +0100 Notification        Display is turned off
            2026-11-27 08:30:00 +0100 Assertions          Summary Using Batt(Charge: 90)
            malformed line without timestamp
            2026-11-27 09:00:00 +0100 \(oversized)
            """
            let buckets = BatteryLogParser.parsePmsetLog(log, now: now)
            assertFalse(buckets.isEmpty)

            let epoch2330 = BatteryHistoryBucket.alignEpoch(fmt.date(from: "2026-11-26T23:30:00+01:00")!)
            let b2330 = buckets.first { $0.bucketStartEpoch == epoch2330 }
            assertNotNil(b2330)
            assertEqual(b2330?.lastChargePercent, 18)
            assertEqual(b2330?.wasCharging, true)

            let epoch0800 = BatteryHistoryBucket.alignEpoch(fmt.date(from: "2026-11-27T08:00:00+01:00")!)
            let b0800 = buckets.first { $0.bucketStartEpoch == epoch0800 }
            assertNotNil(b0800)
            assertEqual(b0800?.lastChargePercent, 95)
            assertEqual(b0800?.wasCharging, false)
            assertTrue((b0800?.screenOnSeconds ?? 0) >= 899, "08:00-08:15 should record full 15m screen-on")

            let hourly = AppEnergyAggregator.hourlyScreenUsage(buckets: buckets, now: now)
            assertEqual(hourly.count, 24)
            let hour08 = hourly.first { Calendar.current.component(.hour, from: $0.hourStart) == 8 && Calendar.current.component(.day, from: $0.hourStart) == 27 }
            assertEqual(hour08?.minutes, 30)
        }

        harness.test("computeDeltas handles PID reuse via startTime and aggregates multi-process apps accurately") {
            let appA = AppEnergyMetadata(id: "bundle:/Applications/melonDS.app", displayName: "melonDS", bundlePath: "/Applications/melonDS.app", bundleIdentifier: nil)
            let appB = AppEnergyMetadata(id: "bundle:/Applications/Brave Browser.app", displayName: "Brave Browser", bundlePath: "/Applications/Brave Browser.app", bundleIdentifier: nil)

            let prev: [ProcessKey: ProcessEnergySnapshot] = [
                ProcessKey(pid: 100, startTime: 111): ProcessEnergySnapshot(pid: 100, startTime: 111, energyNj: 5_000_000_000_000, cpuTimeNs: 10, wakeups: 1, app: appA),
                ProcessKey(pid: 200, startTime: 222): ProcessEnergySnapshot(pid: 200, startTime: 222, energyNj: 100_000_000_000, cpuTimeNs: 5, wakeups: 1, app: appB),
                // Reused PID 300 had huge prior counter
                ProcessKey(pid: 300, startTime: 333): ProcessEnergySnapshot(pid: 300, startTime: 333, energyNj: 9_000_000_000_000, cpuTimeNs: 50, wakeups: 1, app: appB),
            ]
            let curr: [ProcessKey: ProcessEnergySnapshot] = [
                ProcessKey(pid: 100, startTime: 111): ProcessEnergySnapshot(pid: 100, startTime: 111, energyNj: 8_600_000_000_000, cpuTimeNs: 20, wakeups: 2, app: appA), // +1.0 Wh
                ProcessKey(pid: 200, startTime: 222): ProcessEnergySnapshot(pid: 200, startTime: 222, energyNj: 1_900_000_000_000, cpuTimeNs: 8, wakeups: 2, app: appB),   // +0.5 Wh
                // PID 300 was reused with a new startTime 999 -> must NOT subtract prior counter!
                ProcessKey(pid: 300, startTime: 999): ProcessEnergySnapshot(pid: 300, startTime: 999, energyNj: 1_000_000_000, cpuTimeNs: 1, wakeups: 1, app: appB),
            ]

            let delta = AppEnergyAggregator.computeDeltas(previous: prev, current: curr)
            assertEqual(delta.energyByApp[appA.id], 3_600_000_000_000)
            assertEqual(delta.energyByApp[appB.id], 1_800_000_000_000)

            let now = Date()
            let bucket = BatteryHistoryBucket(
                bucketStartEpoch: BatteryHistoryBucket.alignEpoch(now),
                minChargePercent: 50,
                maxChargePercent: 52,
                lastChargePercent: 50,
                wasCharging: false,
                wasExternalConnected: false,
                screenOnSeconds: 600,
                averageDischargeWatts: 10.0,
                appEnergyNj: delta.energyByApp
            )

            let entries = AppEnergyAggregator.aggregateBuckets(
                buckets: [bucket],
                metadata: delta.metadata,
                range: .oneHour,
                selectedBucketEpoch: nil,
                liveWattsByApp: [appA.id: 4.5, appB.id: 0.4],
                batteryCapacityWh: 60.0,
                now: now
            )
            assertEqual(entries.count, 2)
            assertEqual(entries[0].displayName, "melonDS")
            assertTrue(abs(entries[0].energyWh - 1.0) < 0.001)
            assertTrue(entries[0].isSignificant)
            assertFalse(entries[1].isSignificant)
        }
    }

    harness.runSuite("Battery Monitor: Secure History Store") {
        harness.test("store writes 0700/0600 files, caps 96 buckets, and rejects symlinks/corrupt/oversized inputs") {
            let tempRoot = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: tempRoot.url) }

            let store = BatteryHistoryStore(baseURL: tempRoot.url)
            let now = Date()
            let baseEpoch = BatteryHistoryBucket.alignEpoch(now)
            var buckets: [BatteryHistoryBucket] = []
            for i in 0..<120 {
                let epoch = baseEpoch - Int64(119 - i) * BatteryHistoryBucket.durationSeconds
                buckets.append(BatteryHistoryBucket(
                    bucketStartEpoch: epoch,
                    minChargePercent: 50,
                    maxChargePercent: 55,
                    lastChargePercent: 52,
                    wasCharging: false,
                    wasExternalConnected: false
                ))
            }

            let history = BatteryPersistedHistory(recordingStartedAt: now, buckets: buckets, appMetadata: [:])
            try store.save(history)

            let loaded = try store.load()
            assertNotNil(loaded)
            assertEqual(loaded?.buckets.count, 96, "History retention must cap at 96 buckets (24h)")

            let historyFile = tempRoot.url.appendingPathComponent("Yeoman/battery_history/history_v1.json")
            let attrs = try FileManager.default.attributesOfItem(atPath: historyFile.path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
            assertEqual(perms & 0o777, 0o600)

            // Reject corrupt JSON without silent fallback overwrite
            try Data("{not valid json".utf8).write(to: historyFile)
            var corruptRejected = false
            do {
                _ = try store.load()
            } catch {
                corruptRejected = true
            }
            assertTrue(corruptRejected, "Corrupt history JSON must fail closed")

            // Reject symlink replacement
            try FileManager.default.removeItem(at: historyFile)
            let decoy = tempRoot.url.appendingPathComponent("decoy.json")
            try Data("{}".utf8).write(to: decoy)
            try FileManager.default.createSymbolicLink(at: historyFile, withDestinationURL: decoy)
            var symlinkRejected = false
            do {
                _ = try store.load()
            } catch {
                symlinkRejected = true
            }
            assertTrue(symlinkRejected, "Symlinked history file must fail closed")

            // Reject oversized history file (> 2 MB)
            try FileManager.default.removeItem(at: historyFile)
            let oversized = Data(repeating: 0x20, count: BatteryHistoryStore.maxFileBytes + 1024)
            try oversized.write(to: historyFile)
            var oversizedRejected = false
            do {
                _ = try store.load()
            } catch {
                oversizedRejected = true
            }
            assertTrue(oversizedRejected, "Oversized history file must fail closed")
        }
    }

    harness.runSuite("Battery Monitor: Menu Bar Width") {
        harness.test("calculatedStatusItemWidth stays compact without excessive outer padding") {
            let module = BatteryMonitorModule()
            module.menuBarStyle = .iconOnly
            let iconOnlyW = module.calculatedStatusItemWidth()
            module.menuBarStyle = .percentOnly
            let percentW = module.calculatedStatusItemWidth()
            module.menuBarStyle = .iconAndPercent
            let iconPercentW = module.calculatedStatusItemWidth()
            module.menuBarStyle = .iconPercentWatts
            let wattsW = module.calculatedStatusItemWidth()

            assertTrue(iconOnlyW > 0 && iconOnlyW < percentW)
            assertTrue(percentW < iconPercentW && iconPercentW <= 56)
            assertTrue(iconPercentW < wattsW && wattsW <= 92)
        }
    }
}
