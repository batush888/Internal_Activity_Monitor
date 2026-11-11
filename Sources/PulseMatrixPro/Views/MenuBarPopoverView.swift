import SwiftUI
import Charts
import AppKit
import PulseMatrixCore

public struct MenuBarPopoverView: View {
    @ObservedObject var store: SystemMonitorStore
    @Environment(\.openWindow) private var openWindow

    public init(store: SystemMonitorStore) {
        self.store = store
    }

    public var body: some View {
        let snap = store.currentSnapshot
        let topInsight = store.activeInsights.first
        let totalMem = Double(max(1, snap.memory.totalBytes))

        ZStack {
            LiquidGlassWindowBackdrop(glassIntensity: store.glassIntensity)

            VStack(alignment: .leading, spacing: 12) {
                // Header Bar with Live Sparkline
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(PulseTheme.cyanAccent.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "waveform.path.ecg.rectangle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(PulseTheme.cyanAccent)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("PulseMatrix Pro")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(snap.cpu.brandString) • Health \(store.latestHealthReport.overallScore)/100 (\(store.latestHealthReport.overallGrade))")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    Spacer()

                    // Mini Live Sparkline Micro-Chart
                    Chart {
                        ForEach(Array(store.snapshotHistory.suffix(24).enumerated()), id: \.offset) { idx, item in
                            AreaMark(
                                x: .value("T", idx),
                                y: .value("CPU", item.cpu.totalUsagePercent)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [PulseTheme.cyanAccent.opacity(0.45), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("T", idx),
                                y: .value("CPU", item.cpu.totalUsagePercent)
                            )
                            .foregroundStyle(PulseTheme.cyanAccent)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .frame(width: 68, height: 28)

                    Button {
                        store.toggleSessionRecording()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(store.isRecordingSession ? PulseTheme.coral : PulseTheme.emerald)
                                .frame(width: 7, height: 7)
                            Text(store.isRecordingSession ? "\(store.recordingElapsedSeconds)s" : "REC")
                                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(store.isRecordingSession ? PulseTheme.coral.opacity(0.24) : Color.white.opacity(0.10))
                        )
                        .foregroundStyle(store.isRecordingSession ? PulseTheme.coral : .white)
                    }
                    .buttonStyle(.plain)
                }

                // Human-Centric Plain-English Insight Highlight
                if let insight = topInsight {
                    InlineInsightCallout(
                        title: insight.headline,
                        detail: insight.plainEnglishNarrative,
                        severity: insight.severity
                    )
                }

                // 4 Curated Circular Gauges
                HStack(spacing: 12) {
                    CircularMetricGauge(
                        title: "CPU",
                        valueText: String(format: "%.0f%%", snap.cpu.totalUsagePercent),
                        subtitle: "P:\(Int(snap.cpu.performanceClusterUsagePercent))% E:\(Int(snap.cpu.efficiencyClusterUsagePercent))%",
                        progress: snap.cpu.totalUsagePercent,
                        color: PulseTheme.percentageColor(snap.cpu.totalUsagePercent),
                        diameter: 78
                    )
                    CircularMetricGauge(
                        title: "MEMORY",
                        valueText: String(format: "%.0f%%", snap.memory.usagePercent),
                        subtitle: ByteFormatter.formatBytes(snap.memory.usedBytes),
                        progress: snap.memory.usagePercent,
                        color: snap.memory.pressureLevel == .nominal ? PulseTheme.emerald : PulseTheme.amber,
                        diameter: 78
                    )
                    CircularMetricGauge(
                        title: "GPU",
                        valueText: String(format: "%.0f%%", snap.gpu.deviceUtilizationPercent),
                        subtitle: ByteFormatter.formatBytes(snap.gpu.inUseSystemMemoryBytes),
                        progress: snap.gpu.deviceUtilizationPercent,
                        color: PulseTheme.purple,
                        diameter: 78
                    )
                    CircularMetricGauge(
                        title: "THERMAL",
                        valueText: String(format: "%.0f°C", snap.thermal.socPeakTempCelsius),
                        subtitle: String(format: "%.1f W", snap.thermal.privilegedPower?.packagePowerWatts ?? snap.battery.powerWatts),
                        progress: min(100, snap.thermal.socPeakTempCelsius),
                        color: PulseTheme.tempColor(snap.thermal.socPeakTempCelsius),
                        diameter: 78
                    )
                }
                .frame(maxWidth: .infinity)

                // Stacked Unified Memory Composition Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("UNIFIED MEMORY COMPOSITION")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("Swap: \(ByteFormatter.formatBytes(snap.memory.swapUsedBytes))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(snap.memory.swapUsedBytes > 1_073_741_824 ? PulseTheme.amber : .white.opacity(0.6))
                    }

                    StackedCompositionBar(
                        segments: [
                            CompositionSegment(
                                label: "App",
                                valueText: ByteFormatter.formatBytes(snap.memory.appMemoryBytes),
                                proportion: Double(snap.memory.appMemoryBytes) / totalMem,
                                color: PulseTheme.cyanAccent
                            ),
                            CompositionSegment(
                                label: "Wired",
                                valueText: ByteFormatter.formatBytes(snap.memory.wiredBytes),
                                proportion: Double(snap.memory.wiredBytes) / totalMem,
                                color: PulseTheme.amber
                            ),
                            CompositionSegment(
                                label: "Compressed",
                                valueText: ByteFormatter.formatBytes(snap.memory.compressedBytes),
                                proportion: Double(snap.memory.compressedBytes) / totalMem,
                                color: PulseTheme.purple
                            ),
                            CompositionSegment(
                                label: "Free",
                                valueText: ByteFormatter.formatBytes(snap.memory.freeBytes),
                                proportion: Double(snap.memory.freeBytes) / totalMem,
                                color: PulseTheme.emerald.opacity(0.55)
                            )
                        ],
                        barHeight: 10
                    )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

                // Network, Disk & Battery Micro-Strip
                HStack(spacing: 8) {
                    compactPill(
                        icon: "network",
                        label: "Network",
                        value: "↓\(ByteFormatter.formatRate(snap.diskNet.netDownloadBytesPerSec)) ↑\(ByteFormatter.formatRate(snap.diskNet.netUploadBytesPerSec))"
                    )
                    compactPill(
                        icon: "internaldrive.fill",
                        label: "SSD Free",
                        value: ByteFormatter.formatBytes(snap.diskNet.freeDiskBytes)
                    )
                    compactPill(
                        icon: snap.battery.isCharging ? "battery.100.bolt" : "battery.100",
                        label: "Battery",
                        value: "\(Int(snap.battery.chargePercent))% • \(Int(snap.battery.healthPercent))% Hlth"
                    )
                }

                // Liquid Glass Intensity Slider Strip
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.cyanAccent)
                    Text("Glass Intensity")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                    Slider(value: $store.glassIntensity, in: 0.15...0.95)
                        .controlSize(.small)
                    Text("\(Int(store.glassIntensity * 100))%")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(PulseTheme.cyanAccent)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

                // Bottom Action Bar
                HStack(spacing: 8) {
                    Button {
                        openWindow(id: "main-dashboard")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.2x2.fill")
                            Text("Open Dashboard")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 11.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(PulseTheme.cyanAccent.opacity(0.22))
                        .foregroundStyle(PulseTheme.cyanAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.isFloatingHUDVisible.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pip.fill")
                            Text(store.isFloatingHUDVisible ? "Hide HUD" : "PiP HUD")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PulseTheme.purple.opacity(0.24))
                        .foregroundStyle(PulseTheme.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let urls = store.exportHealthReportToDisk() {
                            NSWorkspace.shared.open(urls.htmlURL)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.richtext.fill")
                            Text("Report")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PulseTheme.emerald.opacity(0.22))
                        .foregroundStyle(PulseTheme.emerald)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                            .padding(7)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(15)
        }
        .frame(width: 430)
    }

    private func compactPill(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.cyanAccent)
                Text(label)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
