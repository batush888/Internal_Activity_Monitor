import Foundation

public final class CausalInsightsEngine: Sendable {
    public init() {}

    public func evaluate(
        current: SystemSnapshot,
        history: [SystemSnapshot],
        aiTelemetry: AIProfilerTelemetry? = nil
    ) -> [SystemInsight] {
        var insights: [SystemInsight] = []
        let topCPUProc = current.topProcesses.max(by: { $0.cpuPercent < $1.cpuPercent })
        let topMemProc = current.topProcesses.max(by: { $0.memoryBytes < $1.memoryBytes })

        // 1. Single-Core P-Core Bottleneck Detection (Apple Silicon Specialty)
        if current.cpu.maxSingleCorePercent >= 88.0 && current.cpu.totalUsagePercent < 42.0 {
            let culprit = topCPUProc
            let procDesc = culprit.map { "`\($0.name)` (PID \($0.pid) at \(String(format: "%.1f%%", $0.cpuPercent)) CPU)" } ?? "a single-threaded workload"
            var actions: [InsightRemediationAction] = [
                InsightRemediationAction(
                    label: "Record 30s Bottleneck Trace",
                    kind: .startDiagnosticSession,
                    commandPreview: "Session Recorder -> 1s interval trace"
                )
            ]
            if let c = culprit, c.cpuPercent > 50 {
                actions.append(
                    InsightRemediationAction(
                        label: "Inspect \(c.name)",
                        kind: .inspectProcessInTab,
                        targetPID: c.pid,
                        targetProcessName: c.name
                    )
                )
            }

            insights.append(
                SystemInsight(
                    id: "rule-single-core-bottleneck",
                    severity: .advisory,
                    category: .cpu,
                    ruleIdentifier: "AS-CPU-01",
                    headline: "Single-Thread Bottleneck on Core #\(current.cpu.hottestCoreIndex + 1) (\(String(format: "%.0f%%", current.cpu.maxSingleCorePercent))) Despite \(String(format: "%.0f%%", current.cpu.idlePercent)) System Idle",
                    plainEnglishNarrative: "Overall CPU usage looks low (\(String(format: "%.1f%%", current.cpu.totalUsagePercent))), which hides the real bottleneck: Core #\(current.cpu.hottestCoreIndex + 1) is pinned at \(String(format: "%.1f%%", current.cpu.maxSingleCorePercent)) by \(procDesc). Unparallelized tasks on a single Performance core can make UI interactions or builds feel sluggish even when \(current.cpu.physicalCores - 1) other cores are mostly idle.",
                    rootCauseMetric: "Core #\(current.cpu.hottestCoreIndex + 1): \(String(format: "%.1f%%", current.cpu.maxSingleCorePercent)) vs Total: \(String(format: "%.1f%%", current.cpu.totalUsagePercent))",
                    culpritProcess: culprit,
                    actions: actions
                )
            )
        }

        // 2. P-Cluster Saturation / Heavy Multi-Core Compute
        if current.cpu.performanceClusterUsagePercent >= 78.0 {
            let sev: InsightSeverity = current.cpu.performanceClusterUsagePercent >= 92.0 ? .warning : .advisory
            let culprit = topCPUProc
            let culpritText = culprit.map { "`\($0.name)` (PID \($0.pid)) is consuming \(String(format: "%.1f%%", $0.cpuPercent)) CPU" } ?? "Multiple compute threads are active"
            var actions: [InsightRemediationAction] = []
            if let c = culprit, c.pid > 100 {
                actions.append(
                    InsightRemediationAction(
                        label: "Gracefully Quit \(c.name) (SIGTERM)",
                        kind: .terminateProcessSIGTERM,
                        targetPID: c.pid,
                        targetProcessName: c.name,
                        commandPreview: "kill -15 \(c.pid)"
                    )
                )
            }
            insights.append(
                SystemInsight(
                    id: "rule-pcluster-saturation",
                    severity: sev,
                    category: .cpu,
                    ruleIdentifier: "AS-CPU-02",
                    headline: "Performance Cluster Heavily Loaded (\(String(format: "%.1f%%", current.cpu.performanceClusterUsagePercent)))",
                    plainEnglishNarrative: "Your \(current.cpu.performanceCoreCount) Performance (P) cores are running at \(String(format: "%.1f%%", current.cpu.performanceClusterUsagePercent)) capacity while Efficiency (E) cores are at \(String(format: "%.1f%%", current.cpu.efficiencyClusterUsagePercent)). \(culpritText). Sustained P-core saturation increases package power to ~\(String(format: "%.1fW", current.thermal.privilegedPower?.packagePowerWatts ?? 24.0)) and will ramp fans if maintained for >90 seconds.",
                    rootCauseMetric: "P-Cluster: \(String(format: "%.1f%%", current.cpu.performanceClusterUsagePercent)) | Load 1m: \(String(format: "%.2f", current.cpu.loadAverage1m))",
                    culpritProcess: culprit,
                    actions: actions
                )
            )
        }

        // 3. E-Core Background Spillover
        if current.cpu.efficiencyClusterUsagePercent >= 80.0 && current.cpu.performanceClusterUsagePercent < 35.0 {
            insights.append(
                SystemInsight(
                    id: "rule-ecore-saturation",
                    severity: .advisory,
                    category: .cpu,
                    ruleIdentifier: "AS-CPU-03",
                    headline: "Efficiency (E-Core) Cluster Saturated by Background QoS Tasks (\(String(format: "%.0f%%", current.cpu.efficiencyClusterUsagePercent)))",
                    plainEnglishNarrative: "macOS schedules background daemons (Spotlight `mds_stores`, Time Machine `backupd`, CloudKit, photo analysis) onto your \(current.cpu.efficiencyCoreCount) Efficiency cores using `QoS_CLASS_BACKGROUND`. Right now E-cores are \(String(format: "%.1f%%", current.cpu.efficiencyClusterUsagePercent)) saturated, which keeps your foreground P-cores cool and responsive while background indexing finishes.",
                    rootCauseMetric: "E-Cluster: \(String(format: "%.1f%%", current.cpu.efficiencyClusterUsagePercent)) | P-Cluster: \(String(format: "%.1f%%", current.cpu.performanceClusterUsagePercent))",
                    culpritProcess: topCPUProc
                )
            )
        }

        // 4. Memory Pressure & Active Swap Thrashing Correlation
        let compressedGB = Double(current.memory.compressedBytes) / 1_073_741_824.0
        let swapUsedGB = Double(current.memory.swapUsedBytes) / 1_073_741_824.0
        if current.memory.pressureLevel != .nominal || current.memory.pageoutsPerSec > 10.0 || swapUsedGB > 2.5 {
            let isCrit = current.memory.pressureLevel == .critical || current.memory.pageoutsPerSec > 150.0
            let culprit = topMemProc
            let culpritMemStr = culprit.map { "\($0.name) (\(ByteFormatter.formatBytes($0.memoryBytes)))" } ?? "active applications"
            var actions: [InsightRemediationAction] = [
                InsightRemediationAction(
                    label: "Reclaim Inactive Cache & Inspect Hogs",
                    kind: .reclaimInactiveMemoryHint,
                    commandPreview: "Memory Inspector -> Reclaim & Purge Advisory"
                )
            ]
            if let c = culprit, c.pid > 100 {
                actions.append(
                    InsightRemediationAction(
                        label: "Quit Memory Hog: \(c.name)",
                        kind: .terminateProcessSIGTERM,
                        targetPID: c.pid,
                        targetProcessName: c.name,
                        commandPreview: "kill -15 \(c.pid)"
                    )
                )
            }

            insights.append(
                SystemInsight(
                    id: "rule-memory-swap-thrash",
                    severity: isCrit ? .critical : .warning,
                    category: .memory,
                    ruleIdentifier: "UM-MEM-01",
                    headline: isCrit
                        ? "Active Swap Thrashing & High Unified Memory Pressure (\(String(format: "%.0f%%", current.memory.usagePercent)))"
                        : "Elevated Memory Compression (\(String(format: "%.1f GB", compressedGB))) & Swap Activity",
                    plainEnglishNarrative: "Unified Memory is \(String(format: "%.1f%%", current.memory.usagePercent)) utilized with \(ByteFormatter.formatBytes(current.memory.compressedBytes)) compressed (ratio \(String(format: "%.2fx", current.memory.compressionRatio))) and \(ByteFormatter.formatBytes(current.memory.swapUsedBytes)) spilled to SSD swap at \(String(format: "%.1f", current.memory.pageoutsPerSec)) pageouts/sec. Primary consumer is \(culpritMemStr). High pageout rates steal PCIe bandwidth from your SSD and accelerate NAND wear.",
                    rootCauseMetric: "Pressure: \(current.memory.pressureLevel.rawValue) | Pageouts: \(String(format: "%.1f/s", current.memory.pageoutsPerSec))",
                    culpritProcess: culprit,
                    actions: actions
                )
            )
        }

        // 5. Apple Silicon Unified Memory GPU vs. RAM Contention
        let gpuMemRatio = Double(current.gpu.inUseSystemMemoryBytes) / Double(max(1, current.memory.totalBytes))
        if gpuMemRatio > 0.25 && current.memory.usagePercent > 75.0 {
            insights.append(
                SystemInsight(
                    id: "rule-unified-vram-contention",
                    severity: .warning,
                    category: .gpu,
                    ruleIdentifier: "AS-GPU-01",
                    headline: "Unified Memory Contention Between Metal GPU (\(ByteFormatter.formatBytes(current.gpu.inUseSystemMemoryBytes))) & System RAM",
                    plainEnglishNarrative: "Because Apple Silicon shares a single Unified Memory pool between CPU and GPU, Metal's active allocation of \(ByteFormatter.formatBytes(current.gpu.inUseSystemMemoryBytes)) (\(String(format: "%.0f%%", gpuMemRatio * 100)) of total RAM) is reducing headroom for standard app memory. Consider lowering texture/context batch sizes or closing idle 3D/video/LLM apps.",
                    rootCauseMetric: "GPU VRAM: \(ByteFormatter.formatBytes(current.gpu.inUseSystemMemoryBytes)) | System RAM: \(String(format: "%.1f%%", current.memory.usagePercent))"
                )
            )
        }

        // 6. Thermal Throttling & Fan Acoustic Lag Analysis
        let maxFanUtil = current.thermal.fans.map(\.utilizationPercent).max() ?? 0.0
        if current.thermal.socPeakTempCelsius >= 82.0 || current.thermal.thermalState == .serious || current.thermal.thermalState == .critical {
            let fanLag = maxFanUtil < 45.0
            let narrative: String
            if fanLag {
                narrative = "SoC peak temperature has reached \(String(format: "%.1f°C", current.thermal.socPeakTempCelsius)), but macOS fan hysteresis is keeping fans at only \(String(format: "%.0f%%", maxFanUtil)) speed to prioritize silence. If this workload continues for another 30–45 seconds, fans will ramp sharply or P-core clocks will step down."
            } else {
                narrative = "SoC peak temperature is \(String(format: "%.1f°C", current.thermal.socPeakTempCelsius)) (Thermal State: \(current.thermal.thermalState.rawValue)) with fans actively dissipating heat at \(String(format: "%.0f%%", maxFanUtil)) capacity. Ensure rear/side chassis vents have unobstructed airflow."
            }
            insights.append(
                SystemInsight(
                    id: "rule-thermal-soak",
                    severity: current.thermal.socPeakTempCelsius >= 94.0 ? .critical : .warning,
                    category: .thermal,
                    ruleIdentifier: "THM-01",
                    headline: fanLag
                        ? "Thermal Soak Building (\(String(format: "%.1f°C", current.thermal.socPeakTempCelsius))) Ahead of macOS Fan Ramp"
                        : "High Silicon Thermal Load (\(String(format: "%.1f°C", current.thermal.socPeakTempCelsius))) — Active Cooling Engaged",
                    plainEnglishNarrative: narrative,
                    rootCauseMetric: "SoC Peak: \(String(format: "%.1f°C", current.thermal.socPeakTempCelsius)) | Fan Load: \(String(format: "%.0f%%", maxFanUtil))",
                    culpritProcess: topCPUProc
                )
            )
        }

        // 7. Battery Vampire Drain & Chemical Longevity Analysis
        if current.battery.isPresent {
            if !current.battery.isPluggedIn && current.battery.powerWatts >= 18.5 {
                let culprit = topCPUProc
                let savedMinutes = Int(Double(current.battery.timeRemainingMinutes ?? 120) * 0.28)
                insights.append(
                    SystemInsight(
                        id: "rule-battery-high-discharge",
                        severity: current.battery.powerWatts >= 28.0 ? .warning : .advisory,
                        category: .battery,
                        ruleIdentifier: "BAT-01",
                        headline: "High Battery Discharge Rate (\(String(format: "%.1f W", current.battery.powerWatts))) Reducing Runtime",
                        plainEnglishNarrative: "Your Mac is drawing \(String(format: "%.1f W", current.battery.powerWatts)) from the battery (\(abs(current.battery.amperageMilliamps)) mA at \(String(format: "%.2f V", Double(current.battery.voltageMillivolts) / 1000.0))). Quitting or throttling \(culprit?.name ?? "heavy background tasks") could recover approximately ~\(max(15, savedMinutes)) minutes of battery runtime.",
                        rootCauseMetric: "Discharge: \(String(format: "%.1f W", current.battery.powerWatts)) | Charge: \(String(format: "%.0f%%", current.battery.chargePercent))",
                        culpritProcess: culprit
                    )
                )
            }

            if current.battery.healthPercent < 83.0 || current.battery.cycleCount > 750 {
                insights.append(
                    SystemInsight(
                        id: "rule-battery-chemical-aging",
                        severity: current.battery.healthPercent < 79.0 ? .warning : .advisory,
                        category: .battery,
                        ruleIdentifier: "BAT-02",
                        headline: "Battery Chemical Capacity at \(String(format: "%.1f%%", current.battery.healthPercent)) (\(current.battery.cycleCount) Cycles)",
                        plainEnglishNarrative: "Full charge capacity is now \(current.battery.maxCapacitymAh) mAh vs. factory design capacity of \(current.battery.designCapacitymAh) mAh across \(current.battery.cycleCount) charge cycles. Avoid charging above 35°C (currently \(String(format: "%.1f°C", current.battery.temperatureCelsius))) to slow lithium-ion SEI layer growth.",
                        rootCauseMetric: "Health: \(String(format: "%.1f%%", current.battery.healthPercent)) (\(current.battery.maxCapacitymAh)/\(current.battery.designCapacitymAh) mAh)"
                    )
                )
            }
        }

        // 8. Storage Free Space & APFS Wear-Leveling Guard
        let freeGB = Double(current.diskNet.freeDiskBytes) / 1_073_741_824.0
        if current.diskNet.diskUsagePercent >= 85.0 || freeGB < 28.0 {
            insights.append(
                SystemInsight(
                    id: "rule-ssd-free-space",
                    severity: freeGB < 15.0 ? .critical : .warning,
                    category: .storage,
                    ruleIdentifier: "SSD-01",
                    headline: "Low Free SSD Headroom (\(String(format: "%.1f GB", freeGB)) Free / \(String(format: "%.0f%%", current.diskNet.diskUsagePercent)) Used)",
                    plainEnglishNarrative: "APFS and your Apple NAND controller require at least 10–15% free space to perform efficient wear-leveling and dynamic VM swap file allocation without write amplification. Reclaiming at least 20 GB will improve sustained write speeds and SSD longevity.",
                    rootCauseMetric: "Free: \(ByteFormatter.formatBytes(current.diskNet.freeDiskBytes)) (\(String(format: "%.1f%%", 100.0 - current.diskNet.diskUsagePercent)))"
                )
            )
        }

        // 9. Rolling Z-Score Statistical Anomaly Detector (Historical Baseline Comparison)
        if history.count >= 8 {
            let historicalCPU = history.dropLast().map(\.cpu.totalUsagePercent)
            let meanCPU = historicalCPU.reduce(0.0, +) / Double(historicalCPU.count)
            let varianceCPU = historicalCPU.reduce(0.0) { $0 + pow($1 - meanCPU, 2) } / Double(historicalCPU.count)
            let stdDevCPU = max(2.5, sqrt(varianceCPU))
            let zScoreCPU = (current.cpu.totalUsagePercent - meanCPU) / stdDevCPU

            if zScoreCPU >= 2.6 && (current.cpu.totalUsagePercent - meanCPU) >= 18.0 {
                let culprit = topCPUProc
                insights.append(
                    SystemInsight(
                        id: "rule-zscore-cpu-spike",
                        severity: zScoreCPU >= 3.5 ? .warning : .advisory,
                        category: .anomaly,
                        ruleIdentifier: "STAT-Z01",
                        headline: "Sudden Compute Spike (+\(String(format: "%.1fσ", zScoreCPU)) Above Rolling Baseline)",
                        plainEnglishNarrative: "CPU utilization jumped from your rolling baseline of \(String(format: "%.1f%%", meanCPU)) to \(String(format: "%.1f%%", current.cpu.totalUsagePercent)) (Z-score +\(String(format: "%.2f", zScoreCPU))). Primary contributor is `\(culprit?.name ?? "kernel_task")` (\(String(format: "%.1f%%", culprit?.cpuPercent ?? 0.0)) CPU).",
                        rootCauseMetric: "Current: \(String(format: "%.1f%%", current.cpu.totalUsagePercent)) vs Baseline: \(String(format: "%.1f%%", meanCPU))",
                        zScoreAnomaly: zScoreCPU,
                        culpritProcess: culprit,
                        actions: [
                            InsightRemediationAction(
                                label: "Start 1s Session Recording",
                                kind: .startDiagnosticSession,
                                commandPreview: "Record spike timeline"
                            )
                        ]
                    )
                )
            }
        }

        // 9.5 Local AI / LLM Context Window & KV-Cache Inflation Detection
        if let ai = aiTelemetry, !ai.detectedRuntimes.isEmpty {
            if let heavyLLM = ai.detectedRuntimes.first(where: { ($0.contextWindowTokens ?? $0.envMaxContextTokens ?? 0) >= 65_536 || $0.residentMemoryBytes >= 4 * 1024 * 1024 * 1024 }) {
                let ctx = heavyLLM.contextWindowTokens ?? heavyLLM.envMaxContextTokens ?? 0
                insights.append(
                    SystemInsight(
                        id: "rule-ai-llm-context-kv",
                        severity: ctx >= 65_536 ? .warning : .advisory,
                        category: .gpu,
                        ruleIdentifier: "AI-LLM-01",
                        headline: ctx >= 65_536
                            ? "Oversized LLM Context Window (\(ctx.formatted()) Tokens) on `\(heavyLLM.processName)` (\(ByteFormatter.formatBytes(heavyLLM.residentMemoryBytes)))"
                            : "Active Local AI Runtime `\(heavyLLM.processName)` Using \(ByteFormatter.formatBytes(heavyLLM.residentMemoryBytes)) Unified RAM",
                        plainEnglishNarrative: heavyLLM.contextRiskAdvisory,
                        rootCauseMetric: "AI RAM: \(ByteFormatter.formatBytes(ai.totalAIMemoryBytes)) | Context: \(ctx > 0 ? "\(ctx.formatted()) tok" : "Auto")"
                    )
                )
            }
        }

        // 10. Optimal Healthy System Narrative (Always provide a rich Plain-English explanation even when healthy)
        if insights.isEmpty {
            let pkgW = current.thermal.privilegedPower?.packagePowerWatts ?? 4.5
            let topApp = topCPUProc.map { "`\($0.name)` (\(String(format: "%.1f%%", $0.cpuPercent)) CPU)" } ?? "idle background services"
            insights.append(
                SystemInsight(
                    id: "rule-system-optimal",
                    severity: .optimal,
                    category: .cpu,
                    ruleIdentifier: "SYS-OPT-00",
                    headline: "System Operating in Peak Efficiency Envelope (\(String(format: "%.1f%%", current.cpu.totalUsagePercent)) CPU, \(String(format: "%.1f°C", current.thermal.socAverageTempCelsius)) SoC)",
                    plainEnglishNarrative: "Your \(current.cpu.brandString) is running smoothly with \(String(format: "%.0f%%", current.cpu.idlePercent)) CPU headroom (\(String(format: "%.1f%%", current.cpu.efficiencyClusterUsagePercent)) E-Core load, \(String(format: "%.1f%%", current.cpu.performanceClusterUsagePercent)) P-Core load) and ~\(String(format: "%.1f W", pkgW)) estimated silicon package draw. Unified Memory pressure is \(current.memory.pressureLevel.rawValue) (\(ByteFormatter.formatBytes(current.memory.freeBytes)) available), and the most active process is \(topApp).",
                    rootCauseMetric: "CPU: \(String(format: "%.1f%%", current.cpu.totalUsagePercent)) | RAM: \(String(format: "%.0f%%", current.memory.usagePercent)) | Temp: \(String(format: "%.1f°C", current.thermal.socAverageTempCelsius))",
                    culpritProcess: topCPUProc,
                    actions: [
                        InsightRemediationAction(
                            label: "Copy Plain-English Status Summary",
                            kind: .copyDiagnosticPrescription,
                            commandPreview: "Copy status to clipboard"
                        )
                    ]
                )
            )
        }

        return insights.sorted { $0.severity > $1.severity }
    }

    // MARK: - Human-Centric Inline Card Callouts (Embedded Inside Each Curated Module Card)

    public func inlineModuleCallout(
        for category: InsightCategory,
        snapshot: SystemSnapshot,
        ai: AIProfilerTelemetry? = nil
    ) -> (title: String, detail: String, severity: InsightSeverity) {
        let topCPU = snapshot.topProcesses.max(by: { $0.cpuPercent < $1.cpuPercent })
        let topMem = snapshot.topProcesses.max(by: { $0.memoryBytes < $1.memoryBytes })

        switch category {
        case .cpu, .anomaly:
            if snapshot.cpu.maxSingleCorePercent >= 88.0 && snapshot.cpu.totalUsagePercent < 45.0 {
                return (
                    "Single-Core Bottleneck on Core #\(snapshot.cpu.hottestCoreIndex + 1) (\(Int(snapshot.cpu.maxSingleCorePercent))%)",
                    "Even though total CPU is only \(String(format: "%.0f%%", snapshot.cpu.totalUsagePercent)), Core #\(snapshot.cpu.hottestCoreIndex + 1) is pinned by \(topCPU?.name ?? "an active thread"), limiting single-threaded responsiveness.",
                    .advisory
                )
            } else if snapshot.cpu.performanceClusterUsagePercent >= 75.0 {
                return (
                    "P-Core Cluster Under Heavy Compute (\(String(format: "%.0f%%", snapshot.cpu.performanceClusterUsagePercent)))",
                    "Your \(snapshot.cpu.performanceCoreCount) Performance cores are actively boosting for \(topCPU?.name ?? "compute workloads"), while E-cores handle \(String(format: "%.0f%%", snapshot.cpu.efficiencyClusterUsagePercent)) background load.",
                    .warning
                )
            } else if snapshot.cpu.efficiencyClusterUsagePercent >= 65.0 && snapshot.cpu.performanceClusterUsagePercent < 25.0 {
                return (
                    "Background Tasks Isolated to Efficiency Cores (\(String(format: "%.0f%%", snapshot.cpu.efficiencyClusterUsagePercent)) E-Core)",
                    "macOS QoS is keeping background work on your \(snapshot.cpu.efficiencyCoreCount) E-cores so your \(snapshot.cpu.performanceCoreCount) P-cores remain \(String(format: "%.0f%%", 100 - snapshot.cpu.performanceClusterUsagePercent)) free for instant UI speed.",
                    .optimal
                )
            } else {
                return (
                    "Balanced Apple Silicon Scheduling (\(String(format: "%.0f%%", snapshot.cpu.idlePercent)) Headroom)",
                    "P-Cores are idling at \(String(format: "%.1f%%", snapshot.cpu.performanceClusterUsagePercent)) and E-Cores at \(String(format: "%.1f%%", snapshot.cpu.efficiencyClusterUsagePercent)). Primary active process: \(topCPU?.name ?? "System Idle").",
                    .optimal
                )
            }

        case .memory:
            let swapGB = Double(snapshot.memory.swapUsedBytes) / 1_073_741_824.0
            if snapshot.memory.pressureLevel != .nominal || snapshot.memory.pageoutsPerSec > 10.0 {
                return (
                    "Active Memory Pressure & Pageouts (\(String(format: "%.1f", snapshot.memory.pageoutsPerSec)) pages/s)",
                    "Hardware compressor holds \(ByteFormatter.formatBytes(snapshot.memory.compressedBytes)) (\(String(format: "%.1fx", snapshot.memory.compressionRatio)) ratio) with \(ByteFormatter.formatBytes(snapshot.memory.swapUsedBytes)) on SSD swap. Top consumer: \(topMem?.name ?? "Apps") (\(ByteFormatter.formatBytes(topMem?.memoryBytes ?? 0))).",
                    .warning
                )
            } else if swapGB > 2.5 {
                return (
                    "Nominal Pressure with Historical Swap Footprint (\(ByteFormatter.formatBytes(snapshot.memory.swapUsedBytes)))",
                    "Live RAM pressure is Nominal (\(ByteFormatter.formatBytes(snapshot.memory.freeBytes)) available), though \(ByteFormatter.formatBytes(snapshot.memory.swapUsedBytes)) remains allocated in APFS swap from earlier peak loads.",
                    .advisory
                )
            } else {
                return (
                    "Zero Swap Thrashing — Fast Unified RAM Access",
                    "\(ByteFormatter.formatBytes(snapshot.memory.appMemoryBytes)) in active App RAM and \(ByteFormatter.formatBytes(snapshot.memory.cachedFilesBytes)) in instant-reclaimable file cache.",
                    .optimal
                )
            }

        case .gpu:
            if let ai, !ai.detectedRuntimes.isEmpty {
                let topAI = ai.detectedRuntimes[0]
                let ctx = topAI.contextWindowTokens ?? topAI.envMaxContextTokens ?? 0
                return (
                    "AI Runtime Active: \(topAI.processName) (\(ByteFormatter.formatBytes(ai.totalAIMemoryBytes)))",
                    ctx >= 65_536
                        ? "Running with a large \(ctx.formatted())-token context window. Lowering context size to 16K–32K frees Unified VRAM."
                        : "Metal GPU is at \(String(format: "%.0f%%", snapshot.gpu.deviceUtilizationPercent)) load with \(ByteFormatter.formatBytes(snapshot.gpu.inUseSystemMemoryBytes)) Unified VRAM allocated.",
                    ctx >= 65_536 ? .warning : .advisory
                )
            } else if snapshot.gpu.deviceUtilizationPercent > 65.0 {
                return (
                    "High Metal 3D / Compute Load (\(String(format: "%.0f%%", snapshot.gpu.deviceUtilizationPercent)))",
                    "Your \(snapshot.gpu.coreCount)-core GPU is actively rendering with \(ByteFormatter.formatBytes(snapshot.gpu.inUseSystemMemoryBytes)) Unified VRAM in use.",
                    .advisory
                )
            } else {
                return (
                    "\(snapshot.gpu.coreCount)-Core Metal GPU Ready (\(ByteFormatter.formatBytes(snapshot.gpu.inUseSystemMemoryBytes)) VRAM)",
                    "Unified VRAM is using only \(String(format: "%.1f%%", Double(snapshot.gpu.inUseSystemMemoryBytes) / Double(max(1, snapshot.gpu.recommendedMaxWorkingSetBytes)) * 100.0)) of Metal's \(ByteFormatter.formatBytes(snapshot.gpu.recommendedMaxWorkingSetBytes)) working set limit.",
                    .optimal
                )
            }

        case .thermal:
            let peak = snapshot.thermal.socPeakTempCelsius
            let headroom = max(0.0, 105.0 - peak)
            if peak >= 82.0 {
                return (
                    "Elevated Die Temperature (\(String(format: "%.1f°C", peak)) Peak)",
                    "Only \(String(format: "%.1f°C", headroom)) below silicon throttling threshold. Ensure chassis vents have clear airflow.",
                    .warning
                )
            } else {
                return (
                    "Cool Silicon Envelope (\(String(format: "%.1f°C", headroom)) Thermal Headroom)",
                    "SoC die averages \(String(format: "%.1f°C", snapshot.thermal.socAverageTempCelsius)) (peak \(String(format: "%.1f°C", peak))) at ~\(String(format: "%.1f W", snapshot.thermal.privilegedPower?.packagePowerWatts ?? snapshot.battery.powerWatts)) package power — zero thermal throttling.",
                    .optimal
                )
            }

        case .battery:
            let bat = snapshot.battery
            if !bat.isPluggedIn && bat.powerWatts > 18.0 {
                return (
                    "Elevated Battery Discharge (\(String(format: "%.1f W", bat.powerWatts)))",
                    "High power draw on battery power. Quitting \(topCPU?.name ?? "background tasks") can extend runtime by ~25%.",
                    .warning
                )
            } else {
                return (
                    "Chemical Health at \(String(format: "%.1f%%", bat.healthPercent)) (\(bat.cycleCount) Cycles)",
                    "Full charge capacity is \(bat.maxCapacitymAh) mAh vs \(bat.designCapacitymAh) mAh factory spec at a healthy \(String(format: "%.1f°C", bat.temperatureCelsius)) pack temperature.",
                    bat.healthPercent < 82.0 ? .advisory : .optimal
                )
            }

        case .storage:
            let freePct = 100.0 - snapshot.diskNet.diskUsagePercent
            if freePct < 15.0 {
                return (
                    "Low APFS Free Block Pool (\(String(format: "%.1f%%", freePct)) Free)",
                    "Free at least 20 GB so the SSD controller can wear-level NAND blocks without write amplification.",
                    .warning
                )
            } else {
                return (
                    "Optimal SSD Over-Provisioning (\(ByteFormatter.formatBytes(snapshot.diskNet.freeDiskBytes)) Free)",
                    "APFS has \(String(format: "%.0f%%", freePct)) free capacity with \(ByteFormatter.formatRate(snapshot.diskNet.readBytesPerSec)) read / \(ByteFormatter.formatRate(snapshot.diskNet.writeBytesPerSec)) write throughput.",
                    .optimal
                )
            }

        case .network:
            let totalRate = snapshot.diskNet.netDownloadBytesPerSec + snapshot.diskNet.netUploadBytesPerSec
            if totalRate > 25_000_000 {
                return (
                    "High Network Bandwidth Transfer (\(ByteFormatter.formatRate(totalRate)))",
                    "Active high-speed transfer on \(snapshot.diskNet.primaryInterface) (↓ \(ByteFormatter.formatRate(snapshot.diskNet.netDownloadBytesPerSec)) · ↑ \(ByteFormatter.formatRate(snapshot.diskNet.netUploadBytesPerSec))).",
                    .advisory
                )
            } else {
                return (
                    "Clean Link on \(snapshot.diskNet.primaryInterface) (↓ \(ByteFormatter.formatRate(snapshot.diskNet.netDownloadBytesPerSec)))",
                    "\(snapshot.diskNet.interfaces.count) active interface(s) online with cumulative \(ByteFormatter.formatBytes(snapshot.diskNet.interfaces.reduce(0) { $0 + $1.totalRxBytes })) received.",
                    .optimal
                )
            }
        }
    }
}
