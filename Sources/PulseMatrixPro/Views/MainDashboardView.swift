import SwiftUI
import Charts
import AppKit
import PulseMatrixCore

public struct MainDashboardView: View {
    @ObservedObject var store: SystemMonitorStore

    public init(store: SystemMonitorStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            // Unified Full-Window macOS Liquid Glass Backdrop (Zero Titlebar Separation)
            LiquidGlassWindowBackdrop(glassIntensity: store.glassIntensity)
                .ignoresSafeArea()

            // Cohesive Atmospheric Liquid Glass Tint across the entire window
            LinearGradient(
                colors: [
                    PulseTheme.background.opacity(max(0.18, store.glassIntensity * 0.58)),
                    PulseTheme.cardBackground.opacity(max(0.14, store.glassIntensity * 0.46))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left-Side Liquid Glass Module Menu Bar (Integrates seamlessly with traffic lights)
                liquidGlassLeftMenuSidebar
                    .frame(width: 232)

                // Hairline Refractive Glass Divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .ignoresSafeArea(.container, edges: .vertical)

                // Right Main Content Area with Unified Seamless Header
                VStack(spacing: 0) {
                    liquidGlassSeamlessHeader

                    if let banner = store.statusFeedbackBanner {
                        feedbackBannerView(banner)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 20) {
                            switch store.selectedSection {
                            case .overview:
                                allModulesCuratedBentoView
                            case .siliconTopology:
                                cpuFocusedModuleView
                            case .memoryStorageNet:
                                memoryFocusedModuleView
                            case .aiProfiler:
                                gpuAndAIFocusedModuleView
                            case .thermalAndFans:
                                thermalFocusedModuleView
                            case .batteryLongevity:
                                batteryFocusedModuleView
                            case .diskAndNetwork:
                                diskAndNetFocusedModuleView
                            case .sessionRecorder:
                                sessionsAndHealthModuleView
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Left-Side Liquid Glass Category Menu Bar

    private var liquidGlassLeftMenuSidebar: some View {
        let snap = store.currentSnapshot
        return VStack(alignment: .leading, spacing: 0) {
            // Top Reserve for macOS Window Traffic Lights (Red / Yellow / Green) inside unified glass
            Spacer()
                .frame(height: 36)

            // Brand Identity & Health Score inside Left Menu Bar
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PulseTheme.cyanAccent.opacity(0.32), PulseTheme.purple.opacity(0.24)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(PulseTheme.cyanAccent.opacity(0.45), lineWidth: 0.8)
                        )
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(PulseTheme.cyanAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("PulseMatrix Pro")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(PulseTheme.emerald)
                            .frame(width: 6, height: 6)
                        Text("HEALTH \(store.latestHealthReport.overallScore)/100 (\(store.latestHealthReport.overallGrade))")
                            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                            .foregroundStyle(PulseTheme.emerald)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            Text("SYSTEM MODULES")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            // Vertical Category Menu Items with Live Micro-Telemetry Badges
            VStack(spacing: 5) {
                ForEach(DashboardSection.allCases) { section in
                    let isSelected = store.selectedSection == section
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            store.selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? PulseTheme.cyanAccent.opacity(0.24) : Color.white.opacity(0.05))
                                    .frame(width: 26, height: 26)
                                Image(systemName: section.symbolName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(isSelected ? PulseTheme.cyanAccent : .white.opacity(0.72))
                            }

                            Text(section.rawValue)
                                .font(.system(size: 12.5, weight: isSelected ? .heavy : .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.76))

                            Spacer()

                            if let badge = sidebarLiveBadge(for: section, snapshot: snap) {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6.5)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? PulseTheme.cyanAccent.opacity(0.22) : Color.white.opacity(0.06))
                                    )
                                    .foregroundStyle(isSelected ? PulseTheme.cyanAccent : .white.opacity(0.58))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7.5)
                        .background(
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    PulseTheme.cyanAccent.opacity(0.22),
                                                    PulseTheme.indigo.opacity(0.16)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(PulseTheme.cyanAccent.opacity(0.55), lineWidth: 0.9)
                                } else {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Color.clear)
                                }
                            }
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Bottom Hardware Identity Card inside Left Menu Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PulseTheme.cyanAccent)
                    Text(snap.cpu.brandString)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                Text("\(snap.cpu.performanceCoreCount)P + \(snap.cpu.efficiencyCoreCount)E Cores • \(ByteFormatter.formatBytes(snap.memory.totalBytes)) RAM")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.aiTelemetry.detectedRuntimes.isEmpty ? PulseTheme.emerald : PulseTheme.purple)
                        .frame(width: 6, height: 6)
                    Text(
                        store.aiTelemetry.detectedRuntimes.isEmpty
                            ? "Host: \(snap.hostname)"
                            : "\(store.aiTelemetry.detectedRuntimes.count) Active AI Runtime(s)"
                    )
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(
            Color.white.opacity(0.02)
        )
    }

    private func sidebarLiveBadge(for section: DashboardSection, snapshot snap: SystemSnapshot) -> String? {
        switch section {
        case .overview:
            return "\(store.latestHealthReport.overallGrade)"
        case .siliconTopology:
            return String(format: "%.0f%%", snap.cpu.totalUsagePercent)
        case .memoryStorageNet:
            return String(format: "%.0f%%", snap.memory.usagePercent)
        case .aiProfiler:
            return store.aiTelemetry.detectedRuntimes.isEmpty
                ? String(format: "%.0f%%", snap.gpu.deviceUtilizationPercent)
                : "AI:\(store.aiTelemetry.detectedRuntimes.count)"
        case .thermalAndFans:
            return String(format: "%.0f°C", snap.thermal.socPeakTempCelsius)
        case .batteryLongevity:
            return String(format: "%.0f%%", snap.battery.chargePercent)
        case .diskAndNetwork:
            return ByteFormatter.formatRate(snap.diskNet.netDownloadBytesPerSec + snap.diskNet.netUploadBytesPerSec)
        case .sessionRecorder:
            return store.isRecordingSession ? "REC" : "\(store.savedSessions.count)"
        }
    }

    // MARK: - Seamless Unified Header (Blends with Main Canvas, Zero Color Mismatch)

    private var liquidGlassSeamlessHeader: some View {
        let snap = store.currentSnapshot
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: store.selectedSection.symbolName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PulseTheme.cyanAccent)
                    Text(store.selectedSection.rawValue)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("\(snap.cpu.brandString) • Unified Memory \(ByteFormatter.formatBytes(snap.memory.usedBytes)) / \(ByteFormatter.formatBytes(snap.memory.totalBytes)) • SoC Peak \(String(format: "%.1f°C", snap.thermal.socPeakTempCelsius))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
            }

            Spacer()

            // Live Glass Intensity Slider (Liquid Glass Aesthetic Control)
            HStack(spacing: 7) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(PulseTheme.cyanAccent)
                Text("Glass")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                Slider(value: $store.glassIntensity, in: 0.15...0.95)
                    .frame(width: 92)
                    .controlSize(.small)
                Text("\(Int(store.glassIntensity * 100))%")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(PulseTheme.cyanAccent)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )

            // Floating PiP HUD Toggle
            Button {
                store.isFloatingHUDVisible.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pip.fill")
                    Text(store.isFloatingHUDVisible ? "Hide HUD" : "PiP HUD")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6.5)
                .background(
                    Capsule()
                        .fill(store.isFloatingHUDVisible ? PulseTheme.purple.opacity(0.28) : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .foregroundStyle(store.isFloatingHUDVisible ? PulseTheme.purple : .white.opacity(0.9))
            }
            .buttonStyle(.plain)

            // 1-Second Session Record Button
            Button {
                store.toggleSessionRecording()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.isRecordingSession ? PulseTheme.coral : PulseTheme.emerald)
                        .frame(width: 8, height: 8)
                    Text(store.isRecordingSession ? "REC \(store.recordingElapsedSeconds)s" : "Record Session")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6.5)
                .background(
                    Capsule()
                        .fill(store.isRecordingSession ? PulseTheme.coral.opacity(0.25) : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .foregroundStyle(store.isRecordingSession ? PulseTheme.coral : .white)
            }
            .buttonStyle(.plain)

            // Settings & Customization Popover Button
            Button {
                store.isSettingsPopoverPresented.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.09)))
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $store.isSettingsPopoverPresented, arrowEdge: .bottom) {
                settingsPopoverContent
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Liquid Glass Settings Popover (Glass Intensity, Menu Bar Sparklines, Prometheus)

    private var settingsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Liquid Glass & Interface Settings")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Liquid Glass Intensity (Desktop Bleed-Through)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(store.glassIntensity * 100))%")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(PulseTheme.cyanAccent)
                }
                Slider(value: $store.glassIntensity, in: 0.15...0.95)
                HStack {
                    Text("Clear Liquid (15%)")
                    Spacer()
                    Text("Deep Frosted (95%)")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.5))
            }

            Divider().overlay(Color.white.opacity(0.12))

            Text("Menu Bar Micro-UI & Sparklines")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Live CPU Sparkline (\(store.cpuSparklineUnicode))", isOn: $store.menuBarConfig.showMiniSparkline)
                Toggle("Show CPU Percentage", isOn: $store.menuBarConfig.showCPU)
                Toggle("Show Memory Percentage", isOn: $store.menuBarConfig.showRAM)
                Toggle("Show GPU Percentage", isOn: $store.menuBarConfig.showGPU)
                Toggle("Show SoC Temperature (°C)", isOn: $store.menuBarConfig.showTemp)
                Toggle("Show Live Silicon Wattage (⚡W)", isOn: $store.menuBarConfig.showWatts)
                Toggle("Show Active AI Runtime Badge (🧠)", isOn: $store.menuBarConfig.showAIBadge)
            }
            .font(.system(size: 11.5))

            Divider().overlay(Color.white.opacity(0.12))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prometheus & JSON HTTP Exporter")
                        .font(.system(size: 11.5, weight: .bold))
                    Text("http://\(EnvConfig.shared.prometheusHost):\(store.prometheusServerPort)/metrics")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(PulseTheme.emerald)
                }
                Spacer()
                Button(store.isPrometheusServerRunning ? "Copy URL" : "Start") {
                    if store.isPrometheusServerRunning {
                        store.copyPrometheusEndpoint("/metrics")
                    } else {
                        store.togglePrometheusServer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.cyanAccent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 340)
        .preferredColorScheme(.dark)
    }

    private func feedbackBannerView(_ message: String) -> some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(PulseTheme.cyanAccent)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button("Dismiss") {
                store.statusFeedbackBanner = nil
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(PulseTheme.cyanAccent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(PulseTheme.cyanAccent.opacity(0.16))
    }

    // MARK: - Curated Bento Card Dashboard ("All Modules" View)

    private var allModulesCuratedBentoView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Executive Human-Centric Overview & Circular Gauges Card
            executiveOverviewHeroCard

            // 2. Row 1 of Bento Grid: CPU Card + Unified Memory Card
            HStack(alignment: .top, spacing: 20) {
                curatedCPUCard
                    .frame(maxWidth: .infinity)
                curatedMemoryCard
                    .frame(maxWidth: .infinity)
            }

            // 3. Row 2 of Bento Grid: GPU & Local AI Card + Thermal & Fan Card
            HStack(alignment: .top, spacing: 20) {
                curatedGPUAndAICard
                    .frame(maxWidth: .infinity)
                curatedThermalAndPowerCard
                    .frame(maxWidth: .infinity)
            }

            // 4. Row 3 of Bento Grid: Battery Longevity Card + Disk & Network Card
            HStack(alignment: .top, spacing: 20) {
                curatedBatteryCard
                    .frame(maxWidth: .infinity)
                curatedDiskAndNetworkCard
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Curated Hero Card: Circular Gauges + Human-Centric Plain-English Summary

    private var executiveOverviewHeroCard: some View {
        let snap = store.currentSnapshot
        let pkgWatts = snap.thermal.privilegedPower?.packagePowerWatts ?? snap.battery.powerWatts
        let topInsight = store.activeInsights.first

        return GlassCard(
            title: "SYSTEM PULSE & PLAIN-ENGLISH INTELLIGENCE",
            subtitle: "Real-time hardware telemetry translated into human-readable diagnostics",
            symbol: "sparkles.rectangle.stack.fill",
            badgeText: "1%-LOW STABILITY \(String(format: "%.1f%%", store.liveOnePercentLowStabilityScore))",
            accentColor: PulseTheme.cyanAccent,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 24) {
                    // 5 Overarching Circular Gauges
                    HStack(spacing: 18) {
                        CircularMetricGauge(
                            title: "TOTAL CPU",
                            valueText: String(format: "%.0f%%", snap.cpu.totalUsagePercent),
                            subtitle: "P:\(Int(snap.cpu.performanceClusterUsagePercent))% E:\(Int(snap.cpu.efficiencyClusterUsagePercent))%",
                            progress: snap.cpu.totalUsagePercent,
                            color: PulseTheme.percentageColor(snap.cpu.totalUsagePercent),
                            diameter: 88
                        )
                        CircularMetricGauge(
                            title: "MEMORY",
                            valueText: String(format: "%.0f%%", snap.memory.usagePercent),
                            subtitle: ByteFormatter.formatBytes(snap.memory.usedBytes),
                            progress: snap.memory.usagePercent,
                            color: snap.memory.pressureLevel == .nominal ? PulseTheme.emerald : PulseTheme.amber,
                            diameter: 88
                        )
                        CircularMetricGauge(
                            title: "METAL GPU",
                            valueText: String(format: "%.0f%%", snap.gpu.deviceUtilizationPercent),
                            subtitle: ByteFormatter.formatBytes(snap.gpu.inUseSystemMemoryBytes),
                            progress: snap.gpu.deviceUtilizationPercent,
                            color: PulseTheme.purple,
                            diameter: 88
                        )
                        CircularMetricGauge(
                            title: "SOC TEMP",
                            valueText: String(format: "%.0f°C", snap.thermal.socPeakTempCelsius),
                            subtitle: String(format: "%.1f W", pkgWatts),
                            progress: min(100, snap.thermal.socPeakTempCelsius),
                            color: PulseTheme.tempColor(snap.thermal.socPeakTempCelsius),
                            diameter: 88
                        )
                        CircularMetricGauge(
                            title: "BATTERY",
                            valueText: "\(Int(snap.battery.chargePercent))%",
                            subtitle: "\(Int(snap.battery.healthPercent))% Health",
                            progress: snap.battery.chargePercent,
                            color: PulseTheme.emerald,
                            diameter: 88
                        )
                    }

                    Divider().overlay(Color.white.opacity(0.14)).frame(height: 95)

                    // Primary Human-Centric Plain-English Insight Box
                    if let insight = topInsight {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(insight.severity.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(PulseTheme.color(for: insight.severity).opacity(0.22))
                                    .foregroundStyle(PulseTheme.color(for: insight.severity))
                                    .clipShape(Capsule())
                                Text(insight.headline)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }

                            Text(insight.plainEnglishNarrative)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white.opacity(0.84))
                                .lineLimit(3)

                            if !insight.actions.isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(insight.actions) { action in
                                        Button {
                                            store.executeRemediation(action)
                                        } label: {
                                            Label(action.label, systemImage: "bolt.shield.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(PulseTheme.cyanAccent.opacity(0.18))
                                                .foregroundStyle(PulseTheme.cyanAccent)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Curated Card 1: CPU & Apple Silicon Per-Core Grid + Stacked Composition

    private var curatedCPUCard: some View {
        let snap = store.currentSnapshot
        let callout = store.insightsEngine.inlineModuleCallout(for: .cpu, snapshot: snap, ai: store.aiTelemetry)

        return GlassCard(
            title: "CPU & APPLE SILICON TOPOLOGY",
            subtitle: "\(snap.cpu.brandString) • \(snap.cpu.performanceCoreCount) Performance + \(snap.cpu.efficiencyCoreCount) Efficiency Cores",
            symbol: "cpu.fill",
            badgeText: String(format: "%.1f%% LOAD", snap.cpu.totalUsagePercent),
            accentColor: PulseTheme.cyanAccent,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stacked CPU Composition Bar (User / System / Idle)
                StackedCompositionBar(
                    segments: [
                        CompositionSegment(
                            label: "User Compute",
                            valueText: String(format: "%.1f%%", snap.cpu.userPercent),
                            proportion: snap.cpu.userPercent / 100.0,
                            color: PulseTheme.cyanAccent
                        ),
                        CompositionSegment(
                            label: "Kernel / System",
                            valueText: String(format: "%.1f%%", snap.cpu.systemPercent),
                            proportion: snap.cpu.systemPercent / 100.0,
                            color: PulseTheme.amber
                        ),
                        CompositionSegment(
                            label: "Idle Headroom",
                            valueText: String(format: "%.1f%%", snap.cpu.idlePercent),
                            proportion: snap.cpu.idlePercent / 100.0,
                            color: PulseTheme.emerald.opacity(0.45)
                        )
                    ]
                )

                // Per-Core Grid (Visualizing Individual E-Cores and P-Cores)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("PER-CORE UTILIZATION MATRIX (E-CORES GREEN • P-CORES CYAN)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                        Spacer()
                        Text("Load Avg: \(String(format: "%.2f / %.2f", snap.cpu.loadAverage1m, snap.cpu.loadAverage5m))")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    PerCoreMiniGrid(cores: snap.cpu.perCoreLoads, columnsCount: 5)
                }

                // Embedded Human-Centric Plain-English CPU Callout
                InlineInsightCallout(
                    title: callout.title,
                    detail: callout.detail,
                    severity: callout.severity
                )
            }
        }
    }

    // MARK: - Curated Card 2: Unified Memory Stacked Composition & Pressure

    private var curatedMemoryCard: some View {
        let snap = store.currentSnapshot
        let totalMem = Double(max(1, snap.memory.totalBytes))
        let callout = store.insightsEngine.inlineModuleCallout(for: .memory, snapshot: snap, ai: store.aiTelemetry)

        return GlassCard(
            title: "UNIFIED MEMORY & COMPRESSOR",
            subtitle: "\(ByteFormatter.formatBytes(snap.memory.usedBytes)) used of \(ByteFormatter.formatBytes(snap.memory.totalBytes)) • Compressor \(String(format: "%.1fx", snap.memory.compressionRatio))",
            symbol: "memorychip.fill",
            badgeText: snap.memory.pressureLevel.rawValue.uppercased(),
            accentColor: snap.memory.pressureLevel == .nominal ? PulseTheme.emerald : PulseTheme.amber,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Multi-Layered Stacked Memory Composition Bar
                StackedCompositionBar(
                    segments: [
                        CompositionSegment(
                            label: "App Memory",
                            valueText: ByteFormatter.formatBytes(snap.memory.appMemoryBytes),
                            proportion: Double(snap.memory.appMemoryBytes) / totalMem,
                            color: PulseTheme.cyanAccent
                        ),
                        CompositionSegment(
                            label: "Wired Kernel",
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
                            label: "Cached Files",
                            valueText: ByteFormatter.formatBytes(snap.memory.cachedFilesBytes),
                            proportion: Double(snap.memory.cachedFilesBytes) / totalMem,
                            color: PulseTheme.indigo
                        ),
                        CompositionSegment(
                            label: "Free RAM",
                            valueText: ByteFormatter.formatBytes(snap.memory.freeBytes),
                            proportion: Double(snap.memory.freeBytes) / totalMem,
                            color: PulseTheme.emerald.opacity(0.50)
                        )
                    ]
                )

                // Key Memory Metrics Strip
                HStack(spacing: 12) {
                    miniStatBox("VM Swap Used", ByteFormatter.formatBytes(snap.memory.swapUsedBytes), color: snap.memory.swapUsedBytes > 2_000_000_000 ? PulseTheme.amber : .white)
                    miniStatBox("Page-Ins / s", String(format: "%.1f/s", snap.memory.pageinsPerSec), color: PulseTheme.cyanAccent)
                    miniStatBox("Page-Outs / s", String(format: "%.1f/s", snap.memory.pageoutsPerSec), color: snap.memory.pageoutsPerSec > 5 ? PulseTheme.coral : PulseTheme.emerald)
                }

                // Embedded Human-Centric Plain-English Memory Callout
                InlineInsightCallout(
                    title: callout.title,
                    detail: callout.detail,
                    severity: callout.severity
                )
            }
        }
    }

    // MARK: - Curated Card 3: Metal GPU & Local AI Inference HUD

    private var curatedGPUAndAICard: some View {
        let snap = store.currentSnapshot
        let ai = store.aiTelemetry
        let wired = ai.wiredLimitStatus
        let totalRAM = Double(max(1, snap.memory.totalBytes))
        let inUseVRAM = Double(snap.gpu.inUseSystemMemoryBytes)
        let freePinnable = max(0.0, Double(wired.effectivePinnableBytes) - inUseVRAM)
        let sysReserved = max(0.0, totalRAM - Double(wired.effectivePinnableBytes))
        let callout = store.insightsEngine.inlineModuleCallout(for: .gpu, snapshot: snap, ai: ai)

        return GlassCard(
            title: "METAL GPU & LOCAL AI PROFILER",
            subtitle: "\(snap.gpu.modelName) (\(snap.gpu.coreCount) Cores) • \(ai.detectedRuntimes.count) Active AI Runtime(s)",
            symbol: "cube.transparent.fill",
            badgeText: String(format: "%.1f%% GPU", snap.gpu.deviceUtilizationPercent),
            accentColor: PulseTheme.purple,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stacked Unified VRAM & Metal Wired Limit Composition Bar
                StackedCompositionBar(
                    segments: [
                        CompositionSegment(
                            label: "Active Metal VRAM",
                            valueText: ByteFormatter.formatBytes(snap.gpu.inUseSystemMemoryBytes),
                            proportion: inUseVRAM / totalRAM,
                            color: PulseTheme.purple
                        ),
                        CompositionSegment(
                            label: "Pinnable GPU Headroom",
                            valueText: ByteFormatter.formatBytes(UInt64(freePinnable)),
                            proportion: freePinnable / totalRAM,
                            color: PulseTheme.cyanAccent.opacity(0.65)
                        ),
                        CompositionSegment(
                            label: "macOS Non-Wired Reserve",
                            valueText: ByteFormatter.formatBytes(UInt64(sysReserved)),
                            proportion: sysReserved / totalRAM,
                            color: Color.white.opacity(0.22)
                        )
                    ]
                )

                HStack(spacing: 12) {
                    miniStatBox("Renderer Load", String(format: "%.1f%%", snap.gpu.rendererUtilizationPercent), color: PulseTheme.purple)
                    miniStatBox("Tiler Load", String(format: "%.1f%%", snap.gpu.tilerUtilizationPercent), color: PulseTheme.cyanAccent)
                    miniStatBox("AI Resident RAM", ByteFormatter.formatBytes(ai.totalAIMemoryBytes), color: PulseTheme.emerald)
                }

                // Embedded Human-Centric Plain-English GPU/AI Callout
                InlineInsightCallout(
                    title: callout.title,
                    detail: callout.detail,
                    severity: callout.severity
                )
            }
        }
    }

    // MARK: - Curated Card 4: Thermal Sensors, SMC Fans & Silicon Power Composition

    private var curatedThermalAndPowerCard: some View {
        let snap = store.currentSnapshot
        let pwr = snap.thermal.privilegedPower
        let cpuW = max(0.2, pwr?.cpuPowerWatts ?? 2.0)
        let gpuW = max(0.1, pwr?.gpuPowerWatts ?? 0.8)
        let otherW = max(0.2, (pwr?.dramPowerWatts ?? 0.5) + (pwr?.anePowerWatts ?? 0.1))
        let totalW = cpuW + gpuW + otherW
        let callout = store.insightsEngine.inlineModuleCallout(for: .thermal, snapshot: snap, ai: store.aiTelemetry)

        return GlassCard(
            title: "THERMAL, FANS & SILICON POWER",
            subtitle: "SoC Avg \(String(format: "%.1f°C", snap.thermal.socAverageTempCelsius)) • Peak \(String(format: "%.1f°C", snap.thermal.socPeakTempCelsius)) • \(snap.thermal.thermalState.rawValue)",
            symbol: "thermometer.high",
            badgeText: String(format: "⚡ %.1f W", pwr?.packagePowerWatts ?? snap.battery.powerWatts),
            accentColor: PulseTheme.tempColor(snap.thermal.socPeakTempCelsius),
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stacked Silicon Power Composition Bar
                StackedCompositionBar(
                    segments: [
                        CompositionSegment(
                            label: "CPU Cluster Power",
                            valueText: String(format: "%.2f W", cpuW),
                            proportion: cpuW / totalW,
                            color: PulseTheme.cyanAccent
                        ),
                        CompositionSegment(
                            label: "GPU Power",
                            valueText: String(format: "%.2f W", gpuW),
                            proportion: gpuW / totalW,
                            color: PulseTheme.purple
                        ),
                        CompositionSegment(
                            label: "DRAM & ANE",
                            valueText: String(format: "%.2f W", otherW),
                            proportion: otherW / totalW,
                            color: PulseTheme.amber
                        )
                    ]
                )

                HStack(spacing: 12) {
                    miniStatBox("CPU Die °C", String(format: "%.1f°C", snap.thermal.cpuClusterTempCelsius), color: PulseTheme.tempColor(snap.thermal.cpuClusterTempCelsius))
                    miniStatBox("GPU Die °C", String(format: "%.1f°C", snap.thermal.gpuClusterTempCelsius), color: PulseTheme.tempColor(snap.thermal.gpuClusterTempCelsius))
                    miniStatBox(
                        "Cooling Fans",
                        snap.thermal.fans.isEmpty ? "0 RPM (Silent)" : "\(Int(snap.thermal.fans.map(\.currentRPM).max() ?? 0)) RPM",
                        color: PulseTheme.emerald
                    )
                }

                InlineInsightCallout(
                    title: callout.title,
                    detail: callout.detail,
                    severity: callout.severity
                )
            }
        }
    }

    // MARK: - Curated Card 5: Battery Chemistry & Longevity Composition

    private var curatedBatteryCard: some View {
        let snap = store.currentSnapshot
        let bat = snap.battery
        let designCap = Double(max(1, bat.designCapacitymAh))
        let currCap = Double(bat.currentCapacitymAh)
        let unchargedHealthyCap = Double(max(0, bat.maxCapacitymAh - bat.currentCapacitymAh))
        let degradedLostCap = Double(max(0, bat.designCapacitymAh - bat.maxCapacitymAh))
        let callout = store.insightsEngine.inlineModuleCallout(for: .battery, snapshot: snap, ai: store.aiTelemetry)

        return GlassCard(
            title: "BATTERY CHEMISTRY & POWER DELIVERY",
            subtitle: "\(bat.isPluggedIn ? "AC Power Connected" : "Running on Battery") • \(bat.cycleCount) of 1000 Rated Cycles",
            symbol: bat.isCharging ? "battery.100.bolt" : "battery.100",
            badgeText: "\(Int(bat.chargePercent))% CHARGE • \(String(format: "%.1f%%", bat.healthPercent)) HEALTH",
            accentColor: PulseTheme.emerald,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stacked Chemical Capacity Composition Bar
                StackedCompositionBar(
                    segments: [
                        CompositionSegment(
                            label: "Current Charge",
                            valueText: "\(bat.currentCapacitymAh) mAh",
                            proportion: currCap / designCap,
                            color: PulseTheme.emerald
                        ),
                        CompositionSegment(
                            label: "Available Headroom",
                            valueText: "\(Int(unchargedHealthyCap)) mAh",
                            proportion: unchargedHealthyCap / designCap,
                            color: PulseTheme.cyanAccent.opacity(0.55)
                        ),
                        CompositionSegment(
                            label: "Chemical Aging Loss",
                            valueText: "\(Int(degradedLostCap)) mAh",
                            proportion: degradedLostCap / designCap,
                            color: PulseTheme.coral.opacity(0.75)
                        )
                    ]
                )

                HStack(spacing: 12) {
                    miniStatBox("Pack Voltage", String(format: "%.2f V", Double(bat.voltageMillivolts) / 1000.0), color: PulseTheme.cyanAccent)
                    miniStatBox("Current / Power", String(format: "%.1f W", bat.powerWatts), color: PulseTheme.amber)
                    miniStatBox("Battery Temp", String(format: "%.1f°C", bat.temperatureCelsius), color: PulseTheme.emerald)
                }

                InlineInsightCallout(
                    title: callout.title,
                    detail: callout.detail,
                    severity: callout.severity
                )
            }
        }
    }

    // MARK: - Curated Card 6: Disk & Network Composition

    private var curatedDiskAndNetworkCard: some View {
        let snap = store.currentSnapshot
        let totalDisk = Double(max(1, snap.diskNet.totalDiskBytes))
        let swapBytes = Double(snap.memory.swapUsedBytes)
        let appUsedDisk = max(0.0, Double(snap.diskNet.usedDiskBytes) - swapBytes)
        let freeDisk = Double(snap.diskNet.freeDiskBytes)
        let diskCallout = store.insightsEngine.inlineModuleCallout(for: .storage, snapshot: snap, ai: store.aiTelemetry)

        return GlassCard(
            title: "DISK STORAGE & NETWORK THROUGHPUT",
            subtitle: "\(snap.diskNet.volumeName) (\(snap.diskNet.smartStatus)) • Primary Net: \(snap.diskNet.primaryInterface)",
            symbol: "internaldrive.fill",
            badgeText: "↓\(ByteFormatter.formatRate(snap.diskNet.netDownloadBytesPerSec)) ↑\(ByteFormatter.formatRate(snap.diskNet.netUploadBytesPerSec))",
            accentColor: PulseTheme.indigo,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stacked Storage Composition Bar
                StackedCompositionBar(
                    segments: [
                        CompositionSegment(
                            label: "APFS Volume Data",
                            valueText: ByteFormatter.formatBytes(UInt64(appUsedDisk)),
                            proportion: appUsedDisk / totalDisk,
                            color: PulseTheme.indigo
                        ),
                        CompositionSegment(
                            label: "VM Swap Files",
                            valueText: ByteFormatter.formatBytes(snap.memory.swapUsedBytes),
                            proportion: max(0.015, swapBytes / totalDisk),
                            color: PulseTheme.amber
                        ),
                        CompositionSegment(
                            label: "Free SSD Headroom",
                            valueText: ByteFormatter.formatBytes(snap.diskNet.freeDiskBytes),
                            proportion: freeDisk / totalDisk,
                            color: PulseTheme.emerald.opacity(0.55)
                        )
                    ]
                )

                HStack(spacing: 12) {
                    miniStatBox("SSD Read", ByteFormatter.formatRate(snap.diskNet.readBytesPerSec), color: PulseTheme.cyanAccent)
                    miniStatBox("SSD Write", ByteFormatter.formatRate(snap.diskNet.writeBytesPerSec), color: PulseTheme.purple)
                    miniStatBox("Net Download", ByteFormatter.formatRate(snap.diskNet.netDownloadBytesPerSec), color: PulseTheme.emerald)
                }

                InlineInsightCallout(
                    title: diskCallout.title,
                    detail: diskCallout.detail,
                    severity: diskCallout.severity
                )
            }
        }
    }

    // MARK: - Focused Primary Module Views (When Selecting a Specific Top Pill)

    private var cpuFocusedModuleView: some View {
        VStack(alignment: .leading, spacing: 20) {
            curatedCPUCard

            // Live P-Core vs E-Core Timeline Chart
            GlassCard(
                title: "P-CLUSTER VS E-CLUSTER REAL-TIME TIMELINE",
                subtitle: "1.5-second resolution telemetry across Efficiency and Performance clusters",
                symbol: "chart.xyaxis.line",
                accentColor: PulseTheme.cyanAccent,
                glassIntensity: store.glassIntensity
            ) {
                Chart {
                    ForEach(Array(store.snapshotHistory.enumerated()), id: \.offset) { idx, item in
                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("P-Cluster %", item.cpu.performanceClusterUsagePercent),
                            series: .value("Cluster", "P-Cluster")
                        )
                        .foregroundStyle(PulseTheme.cyanAccent)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("E-Cluster %", item.cpu.efficiencyClusterUsagePercent),
                            series: .value("Cluster", "E-Cluster")
                        )
                        .foregroundStyle(PulseTheme.emerald)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 210)
            }

            // Process Inspector Card
            curatedProcessInspectorCard
        }
    }

    private var memoryFocusedModuleView: some View {
        VStack(alignment: .leading, spacing: 20) {
            curatedMemoryCard
            curatedProcessInspectorCard
        }
    }

    private var gpuAndAIFocusedModuleView: some View {
        let ai = store.aiTelemetry
        let wired = ai.wiredLimitStatus

        return VStack(alignment: .leading, spacing: 20) {
            curatedGPUAndAICard

            // Unified Memory Metal Wired Limit Optimizer Card
            GlassCard(
                title: "METAL UNIFIED VRAM WIRED LIMIT OPTIMIZER (sysctl iogpu.wired_limit_mb)",
                subtitle: wired.plainEnglishAdvice,
                symbol: "bolt.shield.fill",
                badgeText: "SAFE 85%: \(wired.safe85PercentMB) MB",
                accentColor: PulseTheme.cyanAccent,
                glassIntensity: store.glassIntensity
            ) {
                HStack(spacing: 10) {
                    Button {
                        store.applyMetalWiredMemoryLimit(mb: wired.safe85PercentMB)
                    } label: {
                        Label("Apply Safe 85% Wired Limit (\(wired.safe85PercentMB) MB)", systemImage: "bolt.shield.fill")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PulseTheme.emerald.opacity(0.22))
                            .foregroundStyle(PulseTheme.emerald)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.applyMetalWiredMemoryLimit(mb: wired.max90PercentMB)
                    } label: {
                        Label("Apply 90% Limit (\(wired.max90PercentMB) MB)", systemImage: "flame.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PulseTheme.amber.opacity(0.22))
                            .foregroundStyle(PulseTheme.amber)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.applyMetalWiredMemoryLimit(mb: 0)
                    } label: {
                        Label("Reset Default", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.10))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.copyWiredLimitCommand(mb: wired.safe85PercentMB)
                    } label: {
                        Label("Copy sysctl Command", systemImage: "doc.on.doc.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PulseTheme.cyanAccent.opacity(0.20))
                            .foregroundStyle(PulseTheme.cyanAccent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Detected AI Runtimes Cards
            GlassCard(
                title: "ACTIVE LOCAL AI & LLM RUNTIMES (KERN_PROCARGS2 INSPECTOR)",
                subtitle: ai.plainEnglishSummary,
                symbol: "brain.filled.head.profile",
                accentColor: PulseTheme.purple,
                glassIntensity: store.glassIntensity
            ) {
                if ai.detectedRuntimes.isEmpty {
                    Text("No active AI inference processes (`llama-server`, `ollama`, `MLX`, `PyTorch`) are currently loaded in Unified Memory.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    VStack(spacing: 10) {
                        ForEach(ai.detectedRuntimes) { rt in
                            let ctx = rt.contextWindowTokens ?? rt.envMaxContextTokens
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(rt.processName) (PID \(rt.pid))")
                                        .font(.system(size: 13.5, weight: .heavy))
                                        .foregroundStyle(.white)
                                    Text(rt.runtimeFramework)
                                        .font(.system(size: 10.5, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(PulseTheme.purple.opacity(0.22))
                                        .foregroundStyle(PulseTheme.purple)
                                        .clipShape(Capsule())
                                    Spacer()
                                    Text("\(ByteFormatter.formatBytes(rt.residentMemoryBytes)) RAM • Context: \(ctx.map { "\($0.formatted()) tok" } ?? "Default")")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(PulseTheme.cyanAccent)
                                }
                                Text(rt.contextRiskAdvisory)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }

    private var thermalFocusedModuleView: some View {
        let snap = store.currentSnapshot
        return VStack(alignment: .leading, spacing: 20) {
            curatedThermalAndPowerCard

            GlassCard(
                title: "APPLE SILICON DIE & CHASSIS TEMPERATURE SENSORS",
                subtitle: "Direct IOHIDEventSystem & AppleSMC hardware readings",
                symbol: "thermometer.sun.fill",
                accentColor: PulseTheme.amber,
                glassIntensity: store.glassIntensity
            ) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                    ForEach(snap.thermal.sensors) { sensor in
                        HStack {
                            Text(sensor.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f°C", sensor.temperatureCelsius))
                                .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                                .foregroundStyle(PulseTheme.tempColor(sensor.temperatureCelsius))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
    }

    private var batteryFocusedModuleView: some View {
        VStack(alignment: .leading, spacing: 20) {
            curatedBatteryCard
        }
    }

    private var diskAndNetFocusedModuleView: some View {
        let snap = store.currentSnapshot
        return VStack(alignment: .leading, spacing: 20) {
            curatedDiskAndNetworkCard

            GlassCard(
                title: "ACTIVE NETWORK INTERFACES",
                subtitle: "Per-interface live bandwidth & cumulative byte counters",
                symbol: "network",
                accentColor: PulseTheme.emerald,
                glassIntensity: store.glassIntensity
            ) {
                VStack(spacing: 10) {
                    ForEach(snap.diskNet.interfaces) { iface in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(iface.displayName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("IP: \(iface.ipAddress) • RX: \(ByteFormatter.formatBytes(iface.totalRxBytes)) • TX: \(ByteFormatter.formatBytes(iface.totalTxBytes))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Text("↓ \(ByteFormatter.formatRate(iface.rxBytesPerSec))   ↑ \(ByteFormatter.formatRate(iface.txBytesPerSec))")
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(PulseTheme.cyanAccent)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
    }

    // MARK: - Sessions, A/B Lab & 5-Pillar Health Report View

    private var sessionsAndHealthModuleView: some View {
        let report = store.latestHealthReport
        return VStack(alignment: .leading, spacing: 20) {
            // 1. 0–100 Composite Health Report Card
            GlassCard(
                title: "COMPUTER HEALTH & LONGEVITY REPORT CARD",
                subtitle: report.executiveHeadline,
                symbol: "heart.text.square.fill",
                badgeText: "SCORE \(report.overallScore)/100 (\(report.overallGrade))",
                accentColor: PulseTheme.emerald,
                glassIntensity: store.glassIntensity
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(report.executiveNarrative)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.85))

                    StackedCompositionBar(
                        segments: report.pillars.map { p in
                            CompositionSegment(
                                label: p.name,
                                valueText: "\(p.score)/100 (\(p.grade))",
                                proportion: Double(p.weightPercent) / 100.0,
                                color: p.score >= 90 ? PulseTheme.emerald : (p.score >= 80 ? PulseTheme.cyanAccent : PulseTheme.amber)
                            )
                        }
                    )

                    HStack(spacing: 12) {
                        Button {
                            if let urls = store.exportHealthReportToDisk() {
                                NSWorkspace.shared.open(urls.htmlURL)
                            }
                        } label: {
                            Label("Export & Open Interactive HTML Health Report", systemImage: "safari.fill")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(PulseTheme.emerald)
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            _ = store.exportHealthReportToDisk()
                        } label: {
                            Label("Save Markdown & HTML to Disk", systemImage: "doc.text.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.10))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 2. Workload Session Recorder & A/B Comparator Card
            GlassCard(
                title: "1-SECOND PERFORMANCE SESSION RECORDER & A/B COMPARATOR",
                subtitle: "Record Xcode builds, LLM inference, or gaming sessions and compare 1%-Low Stability",
                symbol: "record.circle.fill",
                accentColor: PulseTheme.coral,
                glassIntensity: store.glassIntensity
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        TextField("Session Title", text: $store.recordingTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("Tag", text: $store.recordingWorkloadTag)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        Button {
                            store.toggleSessionRecording()
                        } label: {
                            Label(
                                store.isRecordingSession ? "Stop & Save (\(store.recordingElapsedSeconds)s)" : "Start 1s Recording",
                                systemImage: store.isRecordingSession ? "stop.fill" : "record.circle"
                            )
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(store.isRecordingSession ? PulseTheme.coral : PulseTheme.emerald)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(store.savedSessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title)
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(session.executiveSummary)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            Spacer()
                            Button {
                                _ = store.exportSessionToDisk(session)
                            } label: {
                                Label("Export CSV/JSON", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(PulseTheme.cyanAccent.opacity(0.20))
                                    .foregroundStyle(PulseTheme.cyanAccent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
    }

    // MARK: - Curated Process Cards Grid (Clean Visual Cards Instead of Dense Text Lists)

    private var curatedProcessInspectorCard: some View {
        let filteredProcs = store.currentSnapshot.topProcesses.filter { proc in
            guard !store.processSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
            let q = store.processSearchQuery.lowercased()
            return proc.name.lowercased().contains(q)
                || proc.user.lowercased().contains(q)
                || "\(proc.pid)".contains(q)
        }

        return GlassCard(
            title: "TOP ACTIVE PROCESSES & ENERGY FOOTPRINT",
            subtitle: "Clean visual process cards with 1-click graceful quit or force termination",
            symbol: "square.stack.3d.up.fill",
            accentColor: PulseTheme.cyanAccent,
            glassIntensity: store.glassIntensity
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Search process or PID...", text: $store.processSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 10) {
                    ForEach(filteredProcs.prefix(12)) { proc in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(proc.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("PID \(proc.pid) • \(ByteFormatter.formatBytes(proc.memoryBytes)) RAM")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            Spacer()
                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(proc.cpuPercent > 50 ? PulseTheme.amber : PulseTheme.cyanAccent)

                            Button("Quit") {
                                store.terminateProcess(proc, force: false)
                            }
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PulseTheme.coral.opacity(0.20))
                            .foregroundStyle(PulseTheme.coral)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
    }

    // MARK: - Helper Subviews

    private func miniStatBox(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 13.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
