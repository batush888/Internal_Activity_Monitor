import XCTest
@testable import PulseMatrixCore

final class PulseMatrixProTests: XCTestCase {

    func testLiveAppleSiliconHardwareCollectors() {
        let cpuCollector = MachCPUCollector()
        _ = cpuCollector.sample()
        usleep(100_000)
        let cpu = cpuCollector.sample()

        XCTAssertFalse(cpu.brandString.isEmpty)
        XCTAssertGreaterThanOrEqual(cpu.physicalCores, 4)
        XCTAssertEqual(cpu.perCoreLoads.count, cpu.logicalCores)
        XCTAssertGreaterThanOrEqual(cpu.totalUsagePercent, 0.0)
        XCTAssertLessThanOrEqual(cpu.totalUsagePercent, 100.0)

        let memCollector = MachMemoryCollector()
        let mem = memCollector.sample()
        XCTAssertGreaterThan(mem.totalBytes, 4 * 1024 * 1024 * 1024)
        XCTAssertGreaterThan(mem.usedBytes, 0)
        XCTAssertGreaterThan(mem.usagePercent, 0.0)

        let gpuThermal = IOKitGPUAndThermalCollector()
        let gpu = gpuThermal.sampleGPU()
        XCTAssertFalse(gpu.modelName.isEmpty)
        XCTAssertGreaterThanOrEqual(gpu.coreCount, 8)

        let batteryDiskNet = BatteryDiskNetCollector()
        let bat = batteryDiskNet.sampleBattery()
        XCTAssertGreaterThanOrEqual(bat.chargePercent, 0.0)
        XCTAssertLessThanOrEqual(bat.chargePercent, 100.0)

        let diskNet = batteryDiskNet.sampleDiskAndNetwork()
        XCTAssertGreaterThan(diskNet.totalDiskBytes, 0)
        XCTAssertGreaterThan(diskNet.freeDiskBytes, 0)

        let thermal = gpuThermal.sampleThermalAndFans(
            cpuUsagePercent: cpu.totalUsagePercent,
            gpuUsagePercent: gpu.deviceUtilizationPercent,
            batteryTempCelsius: bat.temperatureCelsius
        )
        XCTAssertGreaterThan(thermal.socPeakTempCelsius, 20.0)
        XCTAssertLessThan(thermal.socPeakTempCelsius, 120.0)
    }

    func testCausalInsightsEngineSingleCoreAndSwapRules() {
        let engine = CausalInsightsEngine()

        let baseSnap = makeSyntheticSnapshot(
            totalCPU: 18.0,
            maxSingleCore: 96.5,
            pCluster: 22.0,
            eCluster: 12.0,
            memUsagePct: 89.0,
            memPressure: .warning,
            pageoutsPerSec: 45.0,
            swapUsedBytes: 4 * 1024 * 1024 * 1024,
            socPeakTemp: 86.0
        )

        let insights = engine.evaluate(current: baseSnap, history: [baseSnap])
        let ruleIDs = Set(insights.map(\.ruleIdentifier))

        XCTAssertTrue(ruleIDs.contains("AS-CPU-01"), "Expected Single-Core P-Core Bottleneck insight")
        XCTAssertTrue(ruleIDs.contains("UM-MEM-01"), "Expected Memory Swap Thrashing insight")
        XCTAssertTrue(ruleIDs.contains("THM-01"), "Expected Thermal Soak insight")
    }

    func testSessionRecorderAndABComparison() {
        let sessionEngine = SessionRecorderEngine()
        let snap1 = makeSyntheticSnapshot(
            totalCPU: 35.0,
            maxSingleCore: 70.0,
            pCluster: 40.0,
            eCluster: 20.0,
            memUsagePct: 55.0,
            memPressure: .nominal,
            pageoutsPerSec: 0.0,
            swapUsedBytes: 0,
            socPeakTemp: 58.0
        )
        let snap2 = makeSyntheticSnapshot(
            totalCPU: 75.0,
            maxSingleCore: 99.0,
            pCluster: 85.0,
            eCluster: 50.0,
            memUsagePct: 80.0,
            memPressure: .warning,
            pageoutsPerSec: 12.0,
            swapUsedBytes: 2 * 1024 * 1024 * 1024,
            socPeakTemp: 88.0
        )

        let now = Date()
        let samplesA = (0..<10).map { sessionEngine.makeSamplePoint(from: snap1, secondOffset: $0) }
        let samplesB = (0..<10).map { sessionEngine.makeSamplePoint(from: snap2, secondOffset: $0) }

        let reportA = sessionEngine.buildReport(
            title: "Session A",
            workloadTag: "Baseline",
            startTime: now.addingTimeInterval(-10),
            endTime: now,
            samples: samplesA
        )
        let reportB = sessionEngine.buildReport(
            title: "Session B",
            workloadTag: "Heavy",
            startTime: now.addingTimeInterval(-10),
            endTime: now,
            samples: samplesB
        )

        XCTAssertEqual(reportA.sampleCount, 10)
        XCTAssertGreaterThan(reportA.onePercentLowStabilityScore, reportB.onePercentLowStabilityScore)

        let comparison = sessionEngine.compare(baseline: reportA, candidate: reportB)
        XCTAssertGreaterThan(comparison.cpuAvgDeltaPercent, 30.0)
        XCTAssertGreaterThan(comparison.peakTempDeltaCelsius, 20.0)

        let csv = sessionEngine.exportCSV(for: reportA)
        XCTAssertTrue(csv.contains("second_offset,timestamp_iso8601,cpu_total_pct"))
    }

    func testHealthReportGenerationAndExport() {
        let healthEngine = HealthReportEngine()
        let snap = makeSyntheticSnapshot(
            totalCPU: 14.0,
            maxSingleCore: 28.0,
            pCluster: 16.0,
            eCluster: 10.0,
            memUsagePct: 52.0,
            memPressure: .nominal,
            pageoutsPerSec: 0.0,
            swapUsedBytes: 0,
            socPeakTemp: 46.0
        )

        let report = healthEngine.generateReport(from: snap, history: [snap])
        XCTAssertEqual(report.pillars.count, 5)
        XCTAssertGreaterThanOrEqual(report.overallScore, 85)

        let html = healthEngine.exportInteractiveHTML(report: report, snapshot: snap)
        let md = healthEngine.exportMarkdown(report: report)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(md.contains("# PulseMatrix Pro — Computer Health & Longevity Audit"))
    }

    func testAIRuntimeProfilerAndContextWindowInspector() {
        let tokens = [
            "/Applications/Ollama.app/Contents/Resources/llama-server",
            "--model",
            "/Users/developer/.ollama/models/blobs/sha256-370c2879f17648d337b0ab4e208fdce348e24d1060064e93d7645daafd56d39c",
            "--port",
            "55874",
            "-c",
            "131072",
            "--spec-draft-model",
            "/Users/developer/.ollama/models/blobs/sha256-05612e54110f8f68bade01dfcc546cdc6914d11dde0b650a65f263f0f87bbbd2",
            "--mmproj",
            "/Users/developer/.ollama/models/blobs/sha256-4cb21b935cd7e79daed76f3154e82f2f160ad7a9d8d22cb5f14c7b93d5fb38ba",
            "OLLAMA_CONTEXT_LENGTH=262144",
            "PWD=/Users/developer"
        ]

        let parsed = AIRuntimeProfilerEngine.parseArgsAndEnv(
            tokens: tokens,
            processName: "llama-server",
            executablePath: "/Applications/Ollama.app/Contents/Resources/llama-server",
            pid: 16710,
            ppid: 15683,
            cpuPercent: 18.5,
            residentBytes: 9_150_000_000
        )

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.contextWindowTokens, 131072)
        XCTAssertEqual(parsed?.envMaxContextTokens, 262144)
        XCTAssertEqual(parsed?.hasSpeculativeDraftModel, true)
        XCTAssertEqual(parsed?.hasMultimodalProjector, true)
        XCTAssertEqual(parsed?.listeningPort, "55874")
        XCTAssertTrue(parsed?.contextRiskAdvisory.contains("Oversized Context Window") == true)

        let aiEngine = AIRuntimeProfilerEngine()
        let wired = aiEngine.evaluateWiredMemoryLimit(
            totalRAMBytes: 32 * 1024 * 1024 * 1024,
            metalRecommendedBytes: 24 * 1024 * 1024 * 1024,
            inUseVRAMBytes: 4 * 1024 * 1024 * 1024
        )
        XCTAssertEqual(wired.safe85PercentMB, 27852)
        XCTAssertEqual(wired.max90PercentMB, 29491)
    }

    func testPrometheusExporterAndLiveAIProfiler() {
        let snap = makeSyntheticSnapshot(
            totalCPU: 25.0,
            maxSingleCore: 60.0,
            pCluster: 30.0,
            eCluster: 15.0,
            memUsagePct: 68.0,
            memPressure: .nominal,
            pageoutsPerSec: 0.0,
            swapUsedBytes: 512 * 1024 * 1024,
            socPeakTemp: 54.0
        )
        let aiEngine = AIRuntimeProfilerEngine()
        let aiTelem = aiEngine.profile(snapshot: snap)
        let health = HealthReportEngine().generateReport(from: snap, history: [snap])

        let prom = PrometheusMetricsServer.formatPrometheusMetrics(
            snapshot: snap,
            aiTelemetry: aiTelem,
            healthReport: health
        )
        XCTAssertTrue(prom.contains("pulsematrix_cpu_usage_percent"))
        XCTAssertTrue(prom.contains("pulsematrix_gpu_vram_bytes{type=\"wired_limit\"}"))
        XCTAssertTrue(prom.contains("pulsematrix_ai_active_processes"))
        XCTAssertTrue(prom.contains("pulsematrix_health_score"))
    }

    func testEnvConfigParserAndAnonymization() {
        let sampleDotEnv = """
        # PulseMatrix Pro Environment Configuration
        PULSEMATRIX_PROMETHEUS_HOST="127.0.0.1"
        PULSEMATRIX_PROMETHEUS_PORT=9195
        PULSEMATRIX_METRICS_API_KEY="secret-local-token"
        PULSEMATRIX_ANONYMIZE_HOST=true
        PULSEMATRIX_REDACTED_HOST_LABEL="apple-silicon-node.local"
        PULSEMATRIX_REDACTED_USER_LABEL="engineer"
        """
        let parsed = EnvConfig.parseDotEnvContents(sampleDotEnv)
        let cfg = EnvConfig(dotenvPath: "/nonexistent/.env", processEnv: parsed)

        XCTAssertEqual(cfg.prometheusHost, "127.0.0.1")
        XCTAssertEqual(cfg.prometheusPort, 9195)
        XCTAssertEqual(cfg.metricsAPIKey, "secret-local-token")
        XCTAssertTrue(cfg.anonymizeHostAndUser)
        XCTAssertEqual(cfg.sanitizeHostname("Private-Mac.local"), "apple-silicon-node.local")
        XCTAssertEqual(cfg.sanitizeUsername("privateuser"), "engineer")
        XCTAssertEqual(cfg.sanitizeUsername("_windowserver"), "_windowserver")
    }

    // MARK: - Helper

    private func makeSyntheticSnapshot(
        totalCPU: Double,
        maxSingleCore: Double,
        pCluster: Double,
        eCluster: Double,
        memUsagePct: Double,
        memPressure: MemoryPressureLevel,
        pageoutsPerSec: Double,
        swapUsedBytes: UInt64,
        socPeakTemp: Double
    ) -> SystemSnapshot {
        let cpu = CPUTelemetry(
            brandString: "Apple M1 Max",
            physicalCores: 10,
            logicalCores: 10,
            efficiencyCoreCount: 2,
            performanceCoreCount: 8,
            totalUsagePercent: totalCPU,
            userPercent: totalCPU * 0.75,
            systemPercent: totalCPU * 0.25,
            idlePercent: 100.0 - totalCPU,
            efficiencyClusterUsagePercent: eCluster,
            performanceClusterUsagePercent: pCluster,
            maxSingleCorePercent: maxSingleCore,
            hottestCoreIndex: 2,
            loadAverage1m: 2.1,
            loadAverage5m: 1.8,
            loadAverage15m: 1.5,
            perCoreLoads: (0..<10).map { idx in
                CoreLoad(
                    coreIndex: idx,
                    cluster: idx < 2 ? .efficiency : .performance,
                    totalUsagePercent: idx == 2 ? maxSingleCore : totalCPU,
                    userPercent: totalCPU * 0.7,
                    systemPercent: totalCPU * 0.3,
                    idlePercent: 100.0 - totalCPU
                )
            }
        )

        let totalBytes: UInt64 = 32 * 1024 * 1024 * 1024
        let usedBytes = UInt64(Double(totalBytes) * (memUsagePct / 100.0))
        let mem = MemoryTelemetry(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            appMemoryBytes: usedBytes / 2,
            wiredBytes: usedBytes / 4,
            compressedBytes: usedBytes / 4,
            cachedFilesBytes: 4 * 1024 * 1024 * 1024,
            freeBytes: totalBytes - usedBytes,
            swapUsedBytes: swapUsedBytes,
            swapTotalBytes: 8 * 1024 * 1024 * 1024,
            pageinsPerSec: 10.0,
            pageoutsPerSec: pageoutsPerSec,
            compressionRatio: 2.4,
            usagePercent: memUsagePct,
            pressureLevel: memPressure
        )

        let gpu = GPUTelemetry(
            modelName: "Apple M1 Max GPU",
            coreCount: 32,
            deviceUtilizationPercent: 18.0,
            rendererUtilizationPercent: 15.0,
            tilerUtilizationPercent: 9.0,
            inUseSystemMemoryBytes: 2 * 1024 * 1024 * 1024,
            allocatedSystemMemoryBytes: 3 * 1024 * 1024 * 1024,
            recommendedMaxWorkingSetBytes: 24 * 1024 * 1024 * 1024
        )

        let thermal = ThermalFanTelemetry(
            thermalState: socPeakTemp > 85 ? .serious : .nominal,
            socAverageTempCelsius: socPeakTemp - 4.0,
            socPeakTempCelsius: socPeakTemp,
            cpuClusterTempCelsius: socPeakTemp,
            gpuClusterTempCelsius: socPeakTemp - 3.0,
            batteryTempCelsius: 30.5,
            ssdTempCelsius: 34.0,
            sensors: [ThermalSensorItem(name: "PMGR SOC Die", temperatureCelsius: socPeakTemp)],
            fans: [FanSensorItem(index: 0, name: "Left Fan", currentRPM: 1800, minRPM: 1200, maxRPM: 5600)]
        )

        let bat = BatteryTelemetry(
            isPresent: true,
            isCharging: false,
            isPluggedIn: true,
            chargePercent: 92.0,
            currentCapacitymAh: 7400,
            maxCapacitymAh: 8000,
            designCapacitymAh: 8600,
            healthPercent: 93.0,
            cycleCount: 145,
            temperatureCelsius: 30.5,
            voltageMillivolts: 12450,
            amperageMilliamps: -950,
            powerWatts: 11.8,
            timeRemainingMinutes: 340,
            conditionLabel: "Normal"
        )

        let diskNet = DiskNetworkTelemetry(
            volumeName: "Macintosh HD",
            totalDiskBytes: 1_000_000_000_000,
            freeDiskBytes: 380_000_000_000,
            usedDiskBytes: 620_000_000_000,
            diskUsagePercent: 62.0,
            readBytesPerSec: 12_000_000,
            writeBytesPerSec: 8_000_000,
            readIOPS: 140,
            writeIOPS: 95,
            totalReadBytes: 50_000_000_000,
            totalWriteBytes: 30_000_000_000,
            smartStatus: "Verified",
            primaryInterface: "en0",
            netDownloadBytesPerSec: 450_000,
            netUploadBytesPerSec: 120_000,
            interfaces: []
        )

        let topProcs = [
            ProcessEntry(
                pid: 4120,
                ppid: 1,
                name: "swift-frontend",
                commandPath: "/Applications/Xcode.app/swift-frontend",
                user: "developer",
                cpuPercent: maxSingleCore,
                memoryBytes: 3_200_000_000,
                stateCode: "R"
            )
        ]

        return SystemSnapshot(
            uptimeSeconds: 86400,
            hostname: "MacBook-Pro.local",
            osVersion: "macOS",
            cpu: cpu,
            memory: mem,
            gpu: gpu,
            thermal: thermal,
            battery: bat,
            diskNet: diskNet,
            topProcesses: topProcs
        )
    }
}
