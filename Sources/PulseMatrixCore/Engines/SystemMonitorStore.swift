import Foundation
import Combine
import AppKit

public enum DashboardSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "All Modules"
    case siliconTopology = "CPU"
    case memoryStorageNet = "Memory"
    case aiProfiler = "GPU & AI"
    case thermalAndFans = "Thermal"
    case batteryLongevity = "Battery"
    case diskAndNetwork = "Disk & Net"
    case sessionRecorder = "Sessions & Health"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .siliconTopology: return "cpu.fill"
        case .memoryStorageNet: return "memorychip.fill"
        case .aiProfiler: return "cube.transparent.fill"
        case .thermalAndFans: return "thermometer.high"
        case .batteryLongevity: return "battery.100.bolt"
        case .diskAndNetwork: return "internaldrive.fill"
        case .sessionRecorder: return "waveform.path.ecg.rectangle.fill"
        }
    }
}

@MainActor
public final class SystemMonitorStore: ObservableObject {
    @Published public private(set) var currentSnapshot: SystemSnapshot
    @Published public private(set) var snapshotHistory: [SystemSnapshot] = []
    @Published public private(set) var activeInsights: [SystemInsight] = []
    @Published public private(set) var latestHealthReport: ComputerHealthReport
    @Published public private(set) var aiTelemetry: AIProfilerTelemetry

    @Published public var selectedSection: DashboardSection = .overview
    @Published public var processSearchQuery: String = ""
    @Published public var statusFeedbackBanner: String? = nil

    // Liquid Glass Aesthetic State (macOS 26/27 Translucent Glass Intensity)
    @Published public var glassIntensity: Double = 0.65
    @Published public var isSettingsPopoverPresented: Bool = false

    // Menu Bar, Floating PiP HUD & Prometheus Exporter State (#7)
    @Published public var menuBarConfig = MenuBarCustomizationConfig()
    @Published public var isFloatingHUDVisible: Bool = false
    @Published public var isFloatingHUDClickThrough: Bool = false
    @Published public var floatingHUDOpacity: Double = 0.92
    @Published public private(set) var isPrometheusServerRunning: Bool = false
    @Published public private(set) var prometheusServerPort: UInt16 = EnvConfig.shared.prometheusPort
    @Published public private(set) var prometheusRequestsServed: Int = 0

    // Session Recording State
    @Published public var isRecordingSession: Bool = false
    @Published public var recordingTitle: String = "Xcode / Compute Workload Trace"
    @Published public var recordingWorkloadTag: String = "Compilation & Compute"
    @Published public private(set) var recordingElapsedSeconds: Int = 0
    @Published public private(set) var currentRecordingSamples: [SessionSamplePoint] = []
    @Published public var savedSessions: [PerformanceSessionReport] = []
    @Published public var baselineSessionID: UUID?
    @Published public var candidateSessionID: UUID?

    // Privileged Powermetrics State
    @Published public private(set) var isPrivilegedPowerActive: Bool = false

    private let cpuCollector = MachCPUCollector()
    private let memoryCollector = MachMemoryCollector()
    private let gpuThermalCollector = IOKitGPUAndThermalCollector()
    private let batteryDiskNetCollector = BatteryDiskNetCollector()
    private let processCollector = ProcessCollector()
    private let powermetricsCollector = PrivilegedPowermetricsCollector()

    public let insightsEngine = CausalInsightsEngine()
    public let sessionEngine = SessionRecorderEngine()
    public let healthEngine = HealthReportEngine()
    public let aiProfilerEngine = AIRuntimeProfilerEngine()
    public let prometheusServer = PrometheusMetricsServer()

    private var timerCancellable: AnyCancellable?
    private var recordingStartTime: Date?
    private let maxHistoryCount = 180

    public init(startPolling: Bool = true) {
        // Prime CPU and Process delta ticks with an initial read
        _ = cpuCollector.sample()
        _ = processCollector.sampleTopProcesses(limit: 10)

        let initialSnap = Self.collectSynchronousSnapshot(
            cpuCollector: cpuCollector,
            memoryCollector: memoryCollector,
            gpuThermalCollector: gpuThermalCollector,
            batteryDiskNetCollector: batteryDiskNetCollector,
            processCollector: processCollector,
            powermetricsCollector: powermetricsCollector
        )
        let initialAI = aiProfilerEngine.profile(snapshot: initialSnap)
        let initialHealth = healthEngine.generateReport(from: initialSnap, history: [initialSnap])

        self.currentSnapshot = initialSnap
        self.snapshotHistory = [initialSnap]
        self.aiTelemetry = initialAI
        self.activeInsights = insightsEngine.evaluate(current: initialSnap, history: [initialSnap], aiTelemetry: initialAI)
        self.latestHealthReport = initialHealth

        prometheusServer.updatePayloads(snapshot: initialSnap, aiTelemetry: initialAI, healthReport: initialHealth)
        let startRes = prometheusServer.start(preferredPort: 9101)
        self.isPrometheusServerRunning = startRes.started
        self.prometheusServerPort = startRes.actualPort

        // Seed 2 reference sessions so A/B Comparison Lab works out of the box
        let seeded = Self.createReferenceBenchmarkSessions(baseSnapshot: initialSnap, engine: sessionEngine)
        self.savedSessions = seeded
        self.baselineSessionID = seeded.first?.id
        self.candidateSessionID = seeded.last?.id

        if startPolling {
            startTelemetryLoop()
        }
    }

    public func startTelemetryLoop() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshNow()
            }
    }

    public func refreshNow() {
        let cpuCol = self.cpuCollector
        let memCol = self.memoryCollector
        let gpuCol = self.gpuThermalCollector
        let bdnCol = self.batteryDiskNetCollector
        let prcCol = self.processCollector
        let pmCol = self.powermetricsCollector
        let aiCol = self.aiProfilerEngine

        Task.detached(priority: .userInitiated) {
            let snap = Self.collectSynchronousSnapshot(
                cpuCollector: cpuCol,
                memoryCollector: memCol,
                gpuThermalCollector: gpuCol,
                batteryDiskNetCollector: bdnCol,
                processCollector: prcCol,
                powermetricsCollector: pmCol
            )
            let ai = aiCol.profile(snapshot: snap)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.ingestSnapshot(snap, ai: ai)
            }
        }
    }

    private func ingestSnapshot(_ snap: SystemSnapshot, ai: AIProfilerTelemetry) {
        self.currentSnapshot = snap
        self.aiTelemetry = ai
        self.snapshotHistory.append(snap)
        if self.snapshotHistory.count > maxHistoryCount {
            self.snapshotHistory.removeFirst(self.snapshotHistory.count - maxHistoryCount)
        }

        self.isPrivilegedPowerActive = snap.thermal.privilegedPower?.isActive ?? false
        self.activeInsights = insightsEngine.evaluate(current: snap, history: snapshotHistory, aiTelemetry: ai)
        self.latestHealthReport = healthEngine.generateReport(from: snap, history: snapshotHistory)

        prometheusServer.updatePayloads(snapshot: snap, aiTelemetry: ai, healthReport: latestHealthReport)
        self.isPrometheusServerRunning = prometheusServer.isRunning
        self.prometheusServerPort = prometheusServer.port
        self.prometheusRequestsServed = prometheusServer.servedRequestsCount

        if isRecordingSession {
            let offset = currentRecordingSamples.count
            let sample = sessionEngine.makeSamplePoint(from: snap, secondOffset: offset)
            currentRecordingSamples.append(sample)
            recordingElapsedSeconds = currentRecordingSamples.count
        }
    }

    // MARK: - Customizable Menu Bar Readout & Mini-Sparkline (#7)

    public var menuBarSummaryText: String {
        var segments: [String] = []
        if menuBarConfig.showMiniSparkline {
            segments.append(cpuSparklineUnicode)
        }
        if menuBarConfig.showCPU {
            let cpuPct = Int(currentSnapshot.cpu.totalUsagePercent.rounded())
            segments.append("CPU \(cpuPct)%")
        }
        if menuBarConfig.showRAM {
            let memPct = Int(currentSnapshot.memory.usagePercent.rounded())
            segments.append("RAM \(memPct)%")
        }
        if menuBarConfig.showGPU {
            let gpuPct = Int(currentSnapshot.gpu.deviceUtilizationPercent.rounded())
            segments.append("GPU \(gpuPct)%")
        }
        if menuBarConfig.showTemp {
            let tempC = Int(currentSnapshot.thermal.socPeakTempCelsius.rounded())
            segments.append("\(tempC)°C")
        }
        if menuBarConfig.showWatts {
            let watts = currentSnapshot.thermal.privilegedPower?.packagePowerWatts ?? currentSnapshot.battery.powerWatts
            segments.append(String(format: "⚡%.0fW", watts))
        }
        if menuBarConfig.showAIBadge && !aiTelemetry.detectedRuntimes.isEmpty {
            segments.append("🧠AI:\(aiTelemetry.detectedRuntimes.count)")
        }
        return segments.isEmpty ? "PulseMatrix" : segments.joined(separator: " · ")
    }

    public var cpuSparklineUnicode: String {
        let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        let recent = snapshotHistory.suffix(6).map(\.cpu.totalUsagePercent)
        guard !recent.isEmpty else { return "▂▃" }
        return String(recent.map { val in
            let idx = min(7, max(0, Int((val / 100.0) * 7.0)))
            return blocks[idx]
        })
    }

    public var liveOnePercentLowStabilityScore: Double {
        let recent = snapshotHistory.suffix(30)
        guard !recent.isEmpty else { return 98.5 }
        let count = Double(recent.count)
        let avgCPU = recent.map(\.cpu.totalUsagePercent).reduce(0.0, +) / count
        let variance = recent.reduce(0.0) { $0 + pow($1.cpu.totalUsagePercent - avgCPU, 2) } / count
        let stdDev = sqrt(variance)
        let peakTemp = recent.map(\.thermal.socPeakTempCelsius).max() ?? 42.0
        let peakSwap = recent.map(\.memory.swapUsedBytes).max() ?? 0
        let thermalPenalty = max(0.0, (peakTemp - 78.0) * 0.9)
        let swapPenalty = min(15.0, Double(peakSwap) / 1_073_741_824.0 * 0.8)
        let jitterPenalty = min(16.0, stdDev * 0.32)
        return max(45.0, min(99.8, 99.0 - thermalPenalty - swapPenalty - jitterPenalty))
    }

    // MARK: - AI Wired Memory & Prometheus Controls (#3 & #7)

    public func applyMetalWiredMemoryLimit(mb: Int) {
        let engine = self.aiProfilerEngine
        Task.detached(priority: .userInitiated) {
            let res = engine.applyWiredLimitMB(mb)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.showBanner(res.message)
                self.refreshNow()
            }
        }
    }

    public func copyWiredLimitCommand(mb: Int) {
        let cmd = "sudo sysctl -w iogpu.wired_limit_mb=\(mb)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        showBanner("Copied '\(cmd)' to clipboard.")
    }

    public func togglePrometheusServer() {
        if prometheusServer.isRunning {
            prometheusServer.stop()
            isPrometheusServerRunning = false
            showBanner("Stopped Prometheus & JSON HTTP Exporter.")
        } else {
            let res = prometheusServer.start(preferredPort: prometheusServerPort)
            isPrometheusServerRunning = res.started
            prometheusServerPort = res.actualPort
            showBanner(res.message)
        }
    }

    public func copyPrometheusEndpoint(_ path: String = "/metrics") {
        let host = EnvConfig.shared.prometheusHost
        let url = "http://\(host):\(prometheusServerPort)\(path)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showBanner("Copied \(url) to clipboard.")
    }

    // MARK: - Session Recording Controls

    public func toggleSessionRecording() {
        if isRecordingSession {
            stopSessionRecording()
        } else {
            startSessionRecording()
        }
    }

    public func startSessionRecording(customTitle: String? = nil, tag: String? = nil) {
        if let customTitle, !customTitle.isEmpty {
            recordingTitle = customTitle
        }
        if let tag, !tag.isEmpty {
            recordingWorkloadTag = tag
        }
        recordingStartTime = Date()
        currentRecordingSamples = [sessionEngine.makeSamplePoint(from: currentSnapshot, secondOffset: 0)]
        recordingElapsedSeconds = 1
        isRecordingSession = true
        showBanner("Started 1-second resolution recording: '\(recordingTitle)'")
    }

    public func stopSessionRecording() {
        guard isRecordingSession else { return }
        isRecordingSession = false
        let end = Date()
        let start = recordingStartTime ?? end.addingTimeInterval(-Double(max(1, currentRecordingSamples.count)))
        let report = sessionEngine.buildReport(
            title: recordingTitle,
            workloadTag: recordingWorkloadTag,
            startTime: start,
            endTime: end,
            samples: currentRecordingSamples
        )
        savedSessions.insert(report, at: 0)
        candidateSessionID = report.id
        if baselineSessionID == nil && savedSessions.count > 1 {
            baselineSessionID = savedSessions[1].id
        }
        showBanner("Saved Performance Session '\(report.title)' (\(report.sampleCount)s, 1%-Low Stability: \(String(format: "%.1f", report.onePercentLowStabilityScore))).")
    }

    // MARK: - Remediation & Diagnostic Actions

    public func executeRemediation(_ action: InsightRemediationAction) {
        switch action.kind {
        case .terminateProcessSIGTERM:
            guard let pid = action.targetPID else { return }
            let result = processCollector.sendSignal(to: pid, signal: SIGTERM)
            showBanner(result.message)
            refreshNow()

        case .terminateProcessSIGKILL:
            guard let pid = action.targetPID else { return }
            let result = processCollector.sendSignal(to: pid, signal: SIGKILL)
            showBanner(result.message)
            refreshNow()

        case .reclaimInactiveMemoryHint:
            selectedSection = .memoryStorageNet
            showBanner("Switched to Memory & Swap Inspector. Identify top resident RAM consumers or run 'sudo purge' in Terminal.")

        case .startDiagnosticSession:
            selectedSection = .sessionRecorder
            if !isRecordingSession {
                startSessionRecording(customTitle: "Diagnostic Bottleneck Trace", tag: "Insight Triggered")
            }

        case .copyDiagnosticPrescription:
            let summary = activeInsights.map { "[\($0.severity.rawValue.uppercased())] \($0.headline)\n\($0.plainEnglishNarrative)" }.joined(separator: "\n\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary, forType: .string)
            showBanner("Copied Plain-English Diagnostic Report to Clipboard.")

        case .inspectProcessInTab:
            if let name = action.targetProcessName {
                processSearchQuery = name
            }
            selectedSection = .siliconTopology
            showBanner("Filtered Process Inspector for '\(action.targetProcessName ?? "process")'.")
        }
    }

    public func terminateProcess(_ entry: ProcessEntry, force: Bool) {
        let sig = force ? SIGKILL : SIGTERM
        let res = processCollector.sendSignal(to: entry.pid, signal: sig)
        showBanner(res.message)
        refreshNow()
    }

    public func unlockPrivilegedPowermetrics() {
        showBanner("Requesting Administrator privileges for Apple Silicon powermetrics...")
        let pmCol = self.powermetricsCollector
        Task.detached(priority: .userInitiated) {
            let result = pmCol.requestPrivilegedSample(interactivePrompt: true)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let telem = result.telemetry {
                    self.isPrivilegedPowerActive = telem.isActive
                    self.showBanner("Unlocked Privileged Powermetrics: Package \(String(format: "%.2f W", telem.packagePowerWatts)) (CPU \(String(format: "%.2f W", telem.cpuPowerWatts)), GPU \(String(format: "%.2f W", telem.gpuPowerWatts))).")
                    self.refreshNow()
                } else {
                    self.showBanner("Using calibrated user-space silicon power model (\(result.error ?? "Standard Mode")).")
                }
            }
        }
    }

    // MARK: - Report & Session Exports

    @discardableResult
    public func exportHealthReportToDisk(directory: URL? = nil) -> (htmlURL: URL, markdownURL: URL)? {
        let targetDir = directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Reports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let htmlContent = healthEngine.exportInteractiveHTML(report: latestHealthReport, snapshot: currentSnapshot)
            let mdContent = healthEngine.exportMarkdown(report: latestHealthReport)

            let htmlURL = targetDir.appendingPathComponent("PulseMatrix_Health_Report.html")
            let mdURL = targetDir.appendingPathComponent("PulseMatrix_Health_Report.md")

            try htmlContent.write(to: htmlURL, atomically: true, encoding: .utf8)
            try mdContent.write(to: mdURL, atomically: true, encoding: .utf8)
            showBanner("Exported Interactive HTML & Markdown Health Reports to \(targetDir.path)")
            return (htmlURL, mdURL)
        } catch {
            showBanner("Failed to export health report: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    public func exportSessionToDisk(_ session: PerformanceSessionReport, directory: URL? = nil) -> (csvURL: URL, jsonURL: URL)? {
        let targetDir = directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Reports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let safeName = session.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: ":", with: "")
            let csvURL = targetDir.appendingPathComponent("Session_\(safeName).csv")
            let jsonURL = targetDir.appendingPathComponent("Session_\(safeName).json")

            let csv = sessionEngine.exportCSV(for: session)
            let json = sessionEngine.exportJSON(for: session)

            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            showBanner("Exported CSV & JSON session data to \(targetDir.path)")
            return (csvURL, jsonURL)
        } catch {
            showBanner("Failed to export session: \(error.localizedDescription)")
            return nil
        }
    }

    public func showBanner(_ message: String) {
        statusFeedbackBanner = message
    }

    // MARK: - Synchronous Collection Helper

    public nonisolated static func collectSynchronousSnapshot(
        cpuCollector: MachCPUCollector,
        memoryCollector: MachMemoryCollector,
        gpuThermalCollector: IOKitGPUAndThermalCollector,
        batteryDiskNetCollector: BatteryDiskNetCollector,
        processCollector: ProcessCollector,
        powermetricsCollector: PrivilegedPowermetricsCollector
    ) -> SystemSnapshot {
        let rawCPU = cpuCollector.sample()
        let mem = memoryCollector.sample()
        let rawGPU = gpuThermalCollector.sampleGPU()
        let battery = batteryDiskNetCollector.sampleBattery()
        let diskNet = batteryDiskNetCollector.sampleDiskAndNetwork()
        let procs = processCollector.sampleTopProcesses(limit: 35)

        let osThermal = ProcessInfo.processInfo.thermalState
        let stateLevel: SystemThermalStateLevel
        switch osThermal {
        case .nominal: stateLevel = .nominal
        case .fair: stateLevel = .fair
        case .serious: stateLevel = .serious
        case .critical: stateLevel = .critical
        @unknown default: stateLevel = .nominal
        }

        let power = powermetricsCollector.currentOrEstimatedPower(
            cpu: rawCPU,
            gpu: rawGPU,
            battery: battery,
            thermal: stateLevel
        )

        let cpuWithFreq = CPUTelemetry(
            brandString: rawCPU.brandString,
            physicalCores: rawCPU.physicalCores,
            logicalCores: rawCPU.logicalCores,
            efficiencyCoreCount: rawCPU.efficiencyCoreCount,
            performanceCoreCount: rawCPU.performanceCoreCount,
            totalUsagePercent: rawCPU.totalUsagePercent,
            userPercent: rawCPU.userPercent,
            systemPercent: rawCPU.systemPercent,
            idlePercent: rawCPU.idlePercent,
            efficiencyClusterUsagePercent: rawCPU.efficiencyClusterUsagePercent,
            performanceClusterUsagePercent: rawCPU.performanceClusterUsagePercent,
            maxSingleCorePercent: rawCPU.maxSingleCorePercent,
            hottestCoreIndex: rawCPU.hottestCoreIndex,
            loadAverage1m: rawCPU.loadAverage1m,
            loadAverage5m: rawCPU.loadAverage5m,
            loadAverage15m: rawCPU.loadAverage15m,
            perCoreLoads: rawCPU.perCoreLoads,
            eClusterFrequencyMHz: power.eClusterFreqMHz,
            pClusterFrequencyMHz: power.pClusterFreqMHz
        )

        let gpuWithPower = GPUTelemetry(
            modelName: rawGPU.modelName,
            coreCount: rawGPU.coreCount,
            deviceUtilizationPercent: rawGPU.deviceUtilizationPercent,
            rendererUtilizationPercent: rawGPU.rendererUtilizationPercent,
            tilerUtilizationPercent: rawGPU.tilerUtilizationPercent,
            inUseSystemMemoryBytes: rawGPU.inUseSystemMemoryBytes,
            allocatedSystemMemoryBytes: rawGPU.allocatedSystemMemoryBytes,
            recommendedMaxWorkingSetBytes: rawGPU.recommendedMaxWorkingSetBytes,
            anePowerWatts: power.anePowerWatts,
            gpuFrequencyMHz: power.gpuFreqMHz
        )

        let thermal = gpuThermalCollector.sampleThermalAndFans(
            cpuUsagePercent: cpuWithFreq.totalUsagePercent,
            gpuUsagePercent: gpuWithPower.deviceUtilizationPercent,
            batteryTempCelsius: battery.temperatureCelsius,
            privilegedPower: power
        )

        let envCfg = EnvConfig.shared
        let sanitizedProcs = procs.map { p in
            ProcessEntry(
                pid: p.pid,
                ppid: p.ppid,
                name: p.name,
                commandPath: p.commandPath,
                user: envCfg.sanitizeUsername(p.user),
                cpuPercent: p.cpuPercent,
                memoryBytes: p.memoryBytes,
                stateCode: p.stateCode,
                isNativeArm64: p.isNativeArm64
            )
        }

        return SystemSnapshot(
            timestamp: Date(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            hostname: envCfg.sanitizeHostname(ProcessInfo.processInfo.hostName),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            cpu: cpuWithFreq,
            memory: mem,
            gpu: gpuWithPower,
            thermal: thermal,
            battery: battery,
            diskNet: diskNet,
            topProcesses: sanitizedProcs
        )
    }

    private nonisolated static func createReferenceBenchmarkSessions(
        baseSnapshot: SystemSnapshot,
        engine: SessionRecorderEngine
    ) -> [PerformanceSessionReport] {
        let now = Date()
        let baseMem = baseSnapshot.memory.usedBytes

        // Session A: Optimized Incremental Build
        var samplesA: [SessionSamplePoint] = []
        for s in 0..<30 {
            let phase = Double(s) / 30.0
            let cpu = 42.0 + sin(phase * .pi) * 28.0
            let pCore = min(100.0, cpu * 1.18)
            let eCore = min(100.0, cpu * 0.55)
            let gpu = 14.0 + cos(phase * .pi) * 8.0
            let temp = 54.0 + phase * 11.5
            let watts = 14.5 + (cpu / 100.0) * 16.0
            samplesA.append(
                SessionSamplePoint(
                    secondOffset: s,
                    timestamp: now.addingTimeInterval(Double(s - 120)),
                    cpuTotalPercent: cpu,
                    pClusterPercent: pCore,
                    eClusterPercent: eCore,
                    maxSingleCorePercent: min(100.0, pCore + 12.0),
                    memoryUsedBytes: baseMem,
                    memoryCompressedBytes: baseSnapshot.memory.compressedBytes,
                    swapUsedBytes: baseSnapshot.memory.swapUsedBytes,
                    gpuUtilizationPercent: gpu,
                    socTempCelsius: temp,
                    fanMaxRPM: 1850 + phase * 400,
                    packageWatts: watts,
                    diskReadBytesPerSec: 45_000_000,
                    diskWriteBytesPerSec: 28_000_000,
                    netRxBytesPerSec: 120_000,
                    netTxBytesPerSec: 45_000,
                    topProcessName: "swift-frontend",
                    topProcessCPUPercent: cpu * 0.85
                )
            )
        }
        let reportA = engine.buildReport(
            title: "Baseline: Swift Incremental Build (Warm Cache)",
            workloadTag: "Xcode Build",
            startTime: now.addingTimeInterval(-120),
            endTime: now.addingTimeInterval(-90),
            samples: samplesA
        )

        // Session B: Uncached Heavy Parallel Build + Metal Shader Compilation
        var samplesB: [SessionSamplePoint] = []
        for s in 0..<30 {
            let phase = Double(s) / 30.0
            let cpu = 68.0 + sin(phase * .pi) * 26.0
            let pCore = min(100.0, cpu * 1.22)
            let eCore = min(100.0, cpu * 0.78)
            let gpu = 48.0 + sin(phase * .pi) * 32.0
            let temp = 64.0 + phase * 21.0
            let watts = 26.0 + (cpu / 100.0) * 24.0
            samplesB.append(
                SessionSamplePoint(
                    secondOffset: s,
                    timestamp: now.addingTimeInterval(Double(s - 60)),
                    cpuTotalPercent: cpu,
                    pClusterPercent: pCore,
                    eClusterPercent: eCore,
                    maxSingleCorePercent: 99.2,
                    memoryUsedBytes: baseMem + 2_147_483_648,
                    memoryCompressedBytes: baseSnapshot.memory.compressedBytes + 1_073_741_824,
                    swapUsedBytes: baseSnapshot.memory.swapUsedBytes + 536_870_912,
                    gpuUtilizationPercent: gpu,
                    socTempCelsius: temp,
                    fanMaxRPM: 2400 + phase * 1450,
                    packageWatts: watts,
                    diskReadBytesPerSec: 145_000_000,
                    diskWriteBytesPerSec: 92_000_000,
                    netRxBytesPerSec: 210_000,
                    netTxBytesPerSec: 85_000,
                    topProcessName: "clang / metal",
                    topProcessCPUPercent: cpu * 0.92
                )
            )
        }
        let reportB = engine.buildReport(
            title: "Candidate: Clean Build + Metal Shader Compile",
            workloadTag: "Heavy Compute + GPU",
            startTime: now.addingTimeInterval(-60),
            endTime: now.addingTimeInterval(-30),
            samples: samplesB
        )

        return [reportB, reportA]
    }
}
