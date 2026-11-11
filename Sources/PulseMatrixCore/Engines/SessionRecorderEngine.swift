import Foundation

public final class SessionRecorderEngine: @unchecked Sendable {
    public init() {}

    public func makeSamplePoint(from snapshot: SystemSnapshot, secondOffset: Int) -> SessionSamplePoint {
        let topProc = snapshot.topProcesses.first
        let maxFan = snapshot.thermal.fans.map(\.currentRPM).max() ?? 0.0
        let pkgWatts = snapshot.thermal.privilegedPower?.packagePowerWatts ?? max(3.5, snapshot.battery.powerWatts)

        return SessionSamplePoint(
            secondOffset: secondOffset,
            timestamp: snapshot.timestamp,
            cpuTotalPercent: snapshot.cpu.totalUsagePercent,
            pClusterPercent: snapshot.cpu.performanceClusterUsagePercent,
            eClusterPercent: snapshot.cpu.efficiencyClusterUsagePercent,
            maxSingleCorePercent: snapshot.cpu.maxSingleCorePercent,
            memoryUsedBytes: snapshot.memory.usedBytes,
            memoryCompressedBytes: snapshot.memory.compressedBytes,
            swapUsedBytes: snapshot.memory.swapUsedBytes,
            gpuUtilizationPercent: snapshot.gpu.deviceUtilizationPercent,
            socTempCelsius: snapshot.thermal.socPeakTempCelsius,
            fanMaxRPM: maxFan,
            packageWatts: pkgWatts,
            diskReadBytesPerSec: snapshot.diskNet.readBytesPerSec,
            diskWriteBytesPerSec: snapshot.diskNet.writeBytesPerSec,
            netRxBytesPerSec: snapshot.diskNet.netDownloadBytesPerSec,
            netTxBytesPerSec: snapshot.diskNet.netUploadBytesPerSec,
            topProcessName: topProc?.name ?? "Idle",
            topProcessCPUPercent: topProc?.cpuPercent ?? 0.0
        )
    }

    public func buildReport(
        title: String,
        workloadTag: String,
        startTime: Date,
        endTime: Date,
        samples: [SessionSamplePoint]
    ) -> PerformanceSessionReport {
        guard !samples.isEmpty else {
            return PerformanceSessionReport(
                id: UUID(),
                title: title,
                workloadTag: workloadTag,
                startTime: startTime,
                endTime: endTime,
                durationSeconds: 0,
                sampleCount: 0,
                avgCPUPercent: 0,
                peakCPUPercent: 0,
                p95CPUPercent: 0,
                p99CPUPercent: 0,
                onePercentLowStabilityScore: 100,
                avgGPUUtilizationPercent: 0,
                peakGPUUtilizationPercent: 0,
                avgMemoryUsedBytes: 0,
                peakMemoryUsedBytes: 0,
                peakSwapUsedBytes: 0,
                avgSoCTempCelsius: 38,
                peakSoCTempCelsius: 38,
                secondsToThermalWarning: nil,
                avgPowerWatts: 4.0,
                estimatedWattHours: 0,
                dominantProcessName: "None",
                executiveSummary: "No telemetry samples recorded.",
                samples: []
            )
        }

        let count = Double(samples.count)
        let sortedCPU = samples.map(\.cpuTotalPercent).sorted()
        let avgCPU = sortedCPU.reduce(0.0, +) / count
        let peakCPU = sortedCPU.last ?? 0.0
        let p95CPU = Self.percentile(sortedCPU, p: 0.95)
        let p99CPU = Self.percentile(sortedCPU, p: 0.99)

        let avgGPU = samples.map(\.gpuUtilizationPercent).reduce(0.0, +) / count
        let peakGPU = samples.map(\.gpuUtilizationPercent).max() ?? 0.0

        let totalMem = samples.reduce(UInt64(0)) { $0 + ($1.memoryUsedBytes / UInt64(max(1, samples.count))) }
        let peakMem = samples.map(\.memoryUsedBytes).max() ?? 0
        let peakSwap = samples.map(\.swapUsedBytes).max() ?? 0

        let avgTemp = samples.map(\.socTempCelsius).reduce(0.0, +) / count
        let peakTemp = samples.map(\.socTempCelsius).max() ?? 38.0
        let thermalWarningIndex = samples.firstIndex(where: { $0.socTempCelsius >= 82.0 })
        let secsToThermal = thermalWarningIndex.map { samples[$0].secondOffset }

        let avgWatts = samples.map(\.packageWatts).reduce(0.0, +) / count
        let durationSecs = max(1, Int(endTime.timeIntervalSince(startTime)))
        let wattHours = avgWatts * (Double(durationSecs) / 3600.0)

        // Compute 1%-Low Stability Score (0-100):
        // Penalizes high thermal variance, swap spikes, and erratic CPU jitter
        let cpuMean = avgCPU
        let cpuVariance = samples.reduce(0.0) { $0 + pow($1.cpuTotalPercent - cpuMean, 2) } / count
        let cpuStdDev = sqrt(cpuVariance)
        let thermalPenalty = max(0.0, (peakTemp - 78.0) * 0.9)
        let swapPenalty = Double(peakSwap) / 1_073_741_824.0 * 3.5
        let jitterPenalty = min(18.0, cpuStdDev * 0.35)
        let stabilityScore = max(40.0, min(99.8, 98.5 - thermalPenalty - swapPenalty - jitterPenalty))

        // Dominant process across samples
        var procCounts: [String: Double] = [:]
        for s in samples {
            procCounts[s.topProcessName, default: 0.0] += max(1.0, s.topProcessCPUPercent)
        }
        let dominantProcess = procCounts.max(by: { $0.value < $1.value })?.key ?? "System"

        let summary = "Recorded \(samples.count)s (\(workloadTag)): Avg CPU \(String(format: "%.1f%%", avgCPU)) (P95 \(String(format: "%.1f%%", p95CPU)), Peak \(String(format: "%.1f%%", peakCPU))), Avg GPU \(String(format: "%.1f%%", avgGPU)), Peak SoC Temp \(String(format: "%.1f°C", peakTemp)), 1%-Low Stability \(String(format: "%.1f", stabilityScore))/100. Dominant process: \(dominantProcess)."

        return PerformanceSessionReport(
            id: UUID(),
            title: title,
            workloadTag: workloadTag,
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSecs,
            sampleCount: samples.count,
            avgCPUPercent: avgCPU,
            peakCPUPercent: peakCPU,
            p95CPUPercent: p95CPU,
            p99CPUPercent: p99CPU,
            onePercentLowStabilityScore: stabilityScore,
            avgGPUUtilizationPercent: avgGPU,
            peakGPUUtilizationPercent: peakGPU,
            avgMemoryUsedBytes: totalMem,
            peakMemoryUsedBytes: peakMem,
            peakSwapUsedBytes: peakSwap,
            avgSoCTempCelsius: avgTemp,
            peakSoCTempCelsius: peakTemp,
            secondsToThermalWarning: secsToThermal,
            avgPowerWatts: avgWatts,
            estimatedWattHours: wattHours,
            dominantProcessName: dominantProcess,
            executiveSummary: summary,
            samples: samples
        )
    }

    public func compare(baseline: PerformanceSessionReport, candidate: PerformanceSessionReport) -> SessionABComparison {
        let cpuDelta = candidate.avgCPUPercent - baseline.avgCPUPercent
        let gpuDelta = candidate.avgGPUUtilizationPercent - baseline.avgGPUUtilizationPercent
        let tempDelta = candidate.peakSoCTempCelsius - baseline.peakSoCTempCelsius
        let memDelta = Int64(candidate.peakMemoryUsedBytes) - Int64(baseline.peakMemoryUsedBytes)
        let stabilityDelta = candidate.onePercentLowStabilityScore - baseline.onePercentLowStabilityScore
        let powerDelta = candidate.avgPowerWatts - baseline.avgPowerWatts

        let tempWord = tempDelta <= 0 ? "\(String(format: "%.1f°C", abs(tempDelta))) cooler" : "\(String(format: "+%.1f°C", tempDelta)) warmer"
        let stabilityWord = stabilityDelta >= 0 ? "+\(String(format: "%.1f", stabilityDelta)) pts more stable" : "\(String(format: "%.1f", stabilityDelta)) pts less stable"
        let powerWord = powerDelta <= 0 ? "\(String(format: "%.1fW", abs(powerDelta))) lower power draw" : "+\(String(format: "%.1fW", powerDelta)) higher power draw"

        let verdict = "Compared to '\(baseline.title)', '\(candidate.title)' ran \(tempWord) at peak, was \(stabilityWord) (1%-Low Stability \(String(format: "%.1f", candidate.onePercentLowStabilityScore)) vs \(String(format: "%.1f", baseline.onePercentLowStabilityScore))), and averaged \(powerWord)."

        return SessionABComparison(
            baseline: baseline,
            candidate: candidate,
            cpuAvgDeltaPercent: cpuDelta,
            gpuAvgDeltaPercent: gpuDelta,
            peakTempDeltaCelsius: tempDelta,
            peakMemoryDeltaBytes: memDelta,
            stabilityScoreDelta: stabilityDelta,
            powerAvgDeltaWatts: powerDelta,
            plainEnglishVerdict: verdict
        )
    }

    public func exportCSV(for report: PerformanceSessionReport) -> String {
        var lines: [String] = [
            "second_offset,timestamp_iso8601,cpu_total_pct,p_cluster_pct,e_cluster_pct,max_single_core_pct,memory_used_bytes,memory_compressed_bytes,swap_used_bytes,gpu_util_pct,soc_temp_c,fan_max_rpm,package_watts,disk_read_bps,disk_write_bps,net_rx_bps,net_tx_bps,top_process,top_process_cpu_pct"
        ]
        let iso = ISO8601DateFormatter()
        for s in report.samples {
            let row = [
                "\(s.secondOffset)",
                iso.string(from: s.timestamp),
                String(format: "%.2f", s.cpuTotalPercent),
                String(format: "%.2f", s.pClusterPercent),
                String(format: "%.2f", s.eClusterPercent),
                String(format: "%.2f", s.maxSingleCorePercent),
                "\(s.memoryUsedBytes)",
                "\(s.memoryCompressedBytes)",
                "\(s.swapUsedBytes)",
                String(format: "%.2f", s.gpuUtilizationPercent),
                String(format: "%.2f", s.socTempCelsius),
                String(format: "%.0f", s.fanMaxRPM),
                String(format: "%.2f", s.packageWatts),
                String(format: "%.0f", s.diskReadBytesPerSec),
                String(format: "%.0f", s.diskWriteBytesPerSec),
                String(format: "%.0f", s.netRxBytesPerSec),
                String(format: "%.0f", s.netTxBytesPerSec),
                "\"\(s.topProcessName.replacingOccurrences(of: "\"", with: "\"\""))\"",
                String(format: "%.2f", s.topProcessCPUPercent)
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    public func exportJSON(for report: PerformanceSessionReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0.0 }
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }
}
