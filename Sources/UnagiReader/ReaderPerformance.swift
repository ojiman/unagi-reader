import AppKit
import os
import ReaderCore
import Darwin

// Opt-in local diagnostics for synthetic acceptance runs. No article IDs, text or URLs are logged.
@MainActor enum ReaderPerformance {
    private static let signposter = OSSignposter(subsystem: AppIdentity.bundleIdentifier, category: "ReaderUI")
    private static var pending: (UUID, Double, OSSignpostIntervalState)?
    private static var samples: [Double] = []
    private static var gaps: [Double] = []
    private static var lastHeartbeat: Double?
    private static var phase: String?
    private static var phaseGaps: [String: [Double]] = [:]
    private static var phaseHeartbeats: [String: Int] = [:]
    private static var launch = Launch()
    static var selectionCount: Int { samples.count }
    static var columnWidths: [String: [String: Double]] = [:]
    static var refreshScenario: String?
    static var output: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--performance-output"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1])
    }
    static func selectionStarted(_ id: UUID) {
        if let old = pending { signposter.endInterval("Selection", old.2) }
        let event = NSApp.currentEvent
        let start = event?.type == .keyDown ? event!.timestamp : ProcessInfo.processInfo.systemUptime
        pending = (id, start, signposter.beginInterval("Selection"))
    }
    static func displayBegan(_ id: UUID) {
        signposter.emitEvent("DisplayBegin")
        guard let value = pending, value.0 == id else { return }
        signposter.endInterval("Selection", value.2); pending = nil
        guard output != nil else { return }
        samples.append(max(0, (ProcessInfo.processInfo.systemUptime - value.1) * 1000))
        write()
    }
    /// A motion starts (issue #212): `MotionMeter` records its frames when the output is on.
    static func motionBegan(_ name: String, duration: Double) {
        guard !ReadingBenchmark.requested else { return }                  // frame-time sampling is outside the reading budgets
        MotionMeter.shared.began(name, duration: duration)
    }
    struct Launch {
        private(set) var milliseconds: Double?
        mutating func drawn(rows: Int, visible: Bool, processStart: Date?, at now: Date) {
            guard milliseconds == nil, rows > 0, visible, let processStart, now >= processStart else { return }
            milliseconds = now.timeIntervalSince(processStart) * 1000
        }
    }
    static func processStart() -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
    static func listDrawn(rows: Int, visible: Bool) {
        guard output != nil, launch.milliseconds == nil else { return }
        launch.drawn(rows: rows, visible: visible, processStart: processStart(), at: .now)
        write()
    }
    static func beginPhase(_ name: String?) {
        heartbeat()                                                       // include any final synchronous work of the preceding phase
        phase = name
        lastHeartbeat = ProcessInfo.processInfo.systemUptime
        if let name { phaseGaps[name] = []; phaseHeartbeats[name] = 0 }
        write()
    }
    static func schedulingGap(previous: Double?, now: Double) -> Double? {
        guard let previous, now - previous > 0.12 else { return nil }
        return (now - previous - 0.02) * 1000
    }
    static func heartbeat() {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastHeartbeat = now }
        if ReadingBenchmark.requested && phase == nil { return }
        if let phase { phaseHeartbeats[phase, default: 0] += 1 }
        if let gap = schedulingGap(previous: lastHeartbeat, now: now) {
            gaps.append(gap)
            if let phase { phaseGaps[phase, default: []].append(gap) }
        }
    }
    static func write() {
        guard let output else { return }
        var values: [String: Any] = ["selectionMilliseconds": samples, "schedulingGapsOver100ms": gaps, "motions": MotionMeter.shared.records,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "displayRefreshRate": CGDisplayCopyDisplayMode(CGMainDisplayID())?.refreshRate ?? 0]
        if !columnWidths.isEmpty { values["columnWidthsPoints"] = columnWidths }
        if let refreshScenario { values["refreshScenario"] = refreshScenario }
        if let milliseconds = launch.milliseconds { values["launchMilliseconds"] = milliseconds }
        if !phaseGaps.isEmpty { values["phaseGapsOver100ms"] = phaseGaps; values["phaseHeartbeatCounts"] = phaseHeartbeats }
        if ReadingBenchmark.requested {
            values["readingBenchmarkComplete"] = ReadingBenchmark.completed
            if let failure = ReadingBenchmark.failure { values["readingBenchmarkError"] = failure }
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: values, options: .sortedKeys).write(to: output, options: .atomic)
        } catch { NSLog("Unagi Reader performance output failed") }
    }
}
