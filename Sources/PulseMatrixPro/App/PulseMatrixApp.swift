import SwiftUI
import AppKit
import PulseMatrixCore

@main
struct PulseMatrixApp: App {
    @StateObject private var store = SystemMonitorStore(startPolling: true)

    init() {
        let args = CommandLine.arguments
        if args.contains("--export-report") {
            let cpuCol = MachCPUCollector()
            let prcCol = ProcessCollector()
            _ = cpuCol.sample()
            _ = prcCol.sampleTopProcesses(limit: 20)
            usleep(180_000)
            let snap = SystemMonitorStore.collectSynchronousSnapshot(
                cpuCollector: cpuCol,
                memoryCollector: MachMemoryCollector(),
                gpuThermalCollector: IOKitGPUAndThermalCollector(),
                batteryDiskNetCollector: BatteryDiskNetCollector(),
                processCollector: prcCol,
                powermetricsCollector: PrivilegedPowermetricsCollector()
            )
            let aiTelemetry = AIRuntimeProfilerEngine().profile(snapshot: snap)
            let insights = CausalInsightsEngine().evaluate(current: snap, history: [snap], aiTelemetry: aiTelemetry)
            let healthEngine = HealthReportEngine()
            let report = healthEngine.generateReport(from: snap, history: [snap])
            let promText = PrometheusMetricsServer.formatPrometheusMetrics(
                snapshot: snap,
                aiTelemetry: aiTelemetry,
                healthReport: report
            )

            let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Reports", isDirectory: true)
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            let htmlURL = outDir.appendingPathComponent("PulseMatrix_Health_Report.html")
            let mdURL = outDir.appendingPathComponent("PulseMatrix_Health_Report.md")
            let promURL = outDir.appendingPathComponent("PulseMatrix_Prometheus_Metrics.prom")
            try? healthEngine.exportInteractiveHTML(report: report, snapshot: snap).write(to: htmlURL, atomically: true, encoding: .utf8)
            try? healthEngine.exportMarkdown(report: report).write(to: mdURL, atomically: true, encoding: .utf8)
            try? promText.write(to: promURL, atomically: true, encoding: .utf8)

            print("=== PulseMatrix Pro Live Hardware & AI Audit ===")
            print("Host: \(snap.hostname) | SoC: \(snap.cpu.brandString) (\(snap.cpu.physicalCores) cores: \(snap.cpu.performanceCoreCount)P + \(snap.cpu.efficiencyCoreCount)E)")
            print("CPU Usage: \(String(format: "%.1f%%", snap.cpu.totalUsagePercent)) (P-Cluster: \(String(format: "%.1f%%", snap.cpu.performanceClusterUsagePercent)), E-Cluster: \(String(format: "%.1f%%", snap.cpu.efficiencyClusterUsagePercent)))")
            print("Unified Memory: \(ByteFormatter.formatBytes(snap.memory.usedBytes)) / \(ByteFormatter.formatBytes(snap.memory.totalBytes)) (\(String(format: "%.1f%%", snap.memory.usagePercent))) | Pressure: \(snap.memory.pressureLevel.rawValue)")
            print("Metal GPU: \(snap.gpu.modelName) (\(snap.gpu.coreCount) cores) | Util: \(String(format: "%.1f%%", snap.gpu.deviceUtilizationPercent)) | VRAM: \(ByteFormatter.formatBytes(snap.gpu.inUseSystemMemoryBytes))")
            print("Metal Wired Limit: \(ByteFormatter.formatBytes(aiTelemetry.wiredLimitStatus.effectivePinnableBytes)) (Safe 85% Ceiling: \(aiTelemetry.wiredLimitStatus.safe85PercentMB) MB)")
            print("AI Runtimes Detected: \(aiTelemetry.detectedRuntimes.count) (Total AI RAM: \(ByteFormatter.formatBytes(aiTelemetry.totalAIMemoryBytes)))")
            for rt in aiTelemetry.detectedRuntimes.prefix(5) {
                let ctx = rt.contextWindowTokens ?? rt.envMaxContextTokens ?? 0
                print("  • [\(rt.runtimeFramework)] \(rt.processName) (PID \(rt.pid)) — RAM: \(ByteFormatter.formatBytes(rt.residentMemoryBytes)), Context: \(ctx > 0 ? "\(ctx) tok" : "default")")
            }
            print("SoC Temp: Avg \(String(format: "%.1f°C", snap.thermal.socAverageTempCelsius)), Peak \(String(format: "%.1f°C", snap.thermal.socPeakTempCelsius))")
            print("Battery: \(String(format: "%.0f%%", snap.battery.chargePercent)) | Health: \(String(format: "%.1f%%", snap.battery.healthPercent)) (\(snap.battery.cycleCount) cycles) | Power: \(String(format: "%.1f W", snap.battery.powerWatts))")
            print("Overall Health Score: \(report.overallScore)/100 (Grade \(report.overallGrade))")
            if let topInsight = insights.first {
                print("Top Plain-English Insight: [\(topInsight.severity.rawValue)] \(topInsight.headline)")
                print("  -> \(topInsight.plainEnglishNarrative)")
            }
            print("Saved HTML Report: \(htmlURL.path)")
            print("Saved Markdown Report: \(mdURL.path)")
            print("Saved Prometheus Metrics: \(promURL.path)")
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("PulseMatrix Pro — Hardware & Insights Command Center", id: "main-dashboard") {
            MainDashboardView(store: store)
                .frame(minWidth: 1160, minHeight: 740)
                .ignoresSafeArea(.container, edges: .top)
                .onAppear {
                    FloatingHUDWindowController.shared.bind(to: store)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1300, height: 850)

        MenuBarExtra {
            MenuBarPopoverView(store: store)
                .onAppear {
                    FloatingHUDWindowController.shared.bind(to: store)
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                Text(store.menuBarSummaryText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
