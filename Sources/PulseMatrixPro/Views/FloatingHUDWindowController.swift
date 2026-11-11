import SwiftUI
import AppKit
import Combine
import PulseMatrixCore

@MainActor
public final class FloatingHUDWindowController {
    public static let shared = FloatingHUDWindowController()
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    public func bind(to store: SystemMonitorStore) {
        cancellables.removeAll()

        store.$isFloatingHUDVisible
            .receive(on: RunLoop.main)
            .sink { [weak self, weak store] visible in
                guard let self, let store else { return }
                if visible {
                    self.showHUD(store: store)
                } else {
                    self.hideHUD()
                }
            }
            .store(in: &cancellables)

        store.$isFloatingHUDClickThrough
            .receive(on: RunLoop.main)
            .sink { [weak self] clickThrough in
                self?.panel?.ignoresMouseEvents = clickThrough
            }
            .store(in: &cancellables)

        store.$floatingHUDOpacity
            .receive(on: RunLoop.main)
            .sink { [weak self] alpha in
                self?.panel?.alphaValue = CGFloat(alpha)
            }
            .store(in: &cancellables)
    }

    public func showHUD(store: SystemMonitorStore) {
        if panel == nil {
            let hudView = FloatingHUDView(store: store)
            let hosting = NSHostingView(rootView: hudView)

            let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let width: CGFloat = 390
            let height: CGFloat = 118
            let initialFrame = NSRect(
                x: screenRect.maxX - width - 24,
                y: screenRect.maxY - height - 24,
                width: width,
                height: height
            )

            let newPanel = NSPanel(
                contentRect: initialFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.isMovableByWindowBackground = true
            newPanel.ignoresMouseEvents = store.isFloatingHUDClickThrough
            newPanel.alphaValue = CGFloat(store.floatingHUDOpacity)
            newPanel.contentView = hosting
            self.panel = newPanel
        }
        panel?.orderFrontRegardless()
    }

    public func hideHUD() {
        panel?.orderOut(nil)
    }
}

public struct FloatingHUDView: View {
    @ObservedObject var store: SystemMonitorStore

    public init(store: SystemMonitorStore) {
        self.store = store
    }

    public var body: some View {
        let snap = store.currentSnapshot
        let pkgWatts = snap.thermal.privilegedPower?.packagePowerWatts ?? snap.battery.powerWatts
        let stability = store.liveOnePercentLowStabilityScore

        VStack(alignment: .leading, spacing: 8) {
            // Top HUD Header
            HStack(spacing: 8) {
                Circle()
                    .fill(PulseTheme.emerald)
                    .frame(width: 7, height: 7)
                Text("PULSEMATRIX HUD")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(PulseTheme.cyanAccent)

                Text("• 1%-Low \(String(format: "%.1f%%", stability))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(PulseTheme.emerald)

                Spacer()

                if store.isFloatingHUDClickThrough {
                    Text("CLICK-THROUGH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(PulseTheme.amber)
                }

                Button {
                    store.isFloatingHUDVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }

            // 4 High-Contrast Telemetry Columns
            HStack(spacing: 14) {
                hudMetric(
                    label: "CPU (P/E)",
                    value: String(format: "%.0f%%", snap.cpu.totalUsagePercent),
                    sub: "P:\(Int(snap.cpu.performanceClusterUsagePercent))% E:\(Int(snap.cpu.efficiencyClusterUsagePercent))%",
                    color: PulseTheme.cyanAccent
                )
                hudMetric(
                    label: "GPU / VRAM",
                    value: String(format: "%.0f%%", snap.gpu.deviceUtilizationPercent),
                    sub: ByteFormatter.formatBytes(snap.gpu.inUseSystemMemoryBytes),
                    color: PulseTheme.purple
                )
                hudMetric(
                    label: "SOC TEMP",
                    value: String(format: "%.1f°C", snap.thermal.socPeakTempCelsius),
                    sub: snap.thermal.thermalState.rawValue,
                    color: PulseTheme.tempColor(snap.thermal.socPeakTempCelsius)
                )
                hudMetric(
                    label: "POWER",
                    value: String(format: "%.1fW", pkgWatts),
                    sub: "RAM \(Int(snap.memory.usagePercent))%",
                    color: PulseTheme.amber
                )
            }

            // Bottom AI / Process Strip
            HStack {
                if let topAI = store.aiTelemetry.detectedRuntimes.first {
                    Text("🧠 AI: \(topAI.processName) (\(ByteFormatter.formatBytes(topAI.residentMemoryBytes)))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PulseTheme.emerald)
                } else if let topProc = snap.topProcesses.first {
                    Text("Top: \(topProc.name) (\(String(format: "%.1f%%", topProc.cpuPercent)) CPU)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Text("↓\(ByteFormatter.formatRate(snap.diskNet.netDownloadBytesPerSec)) ↑\(ByteFormatter.formatRate(snap.diskNet.netUploadBytesPerSec))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.11).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseTheme.cyanAccent.opacity(0.45), lineWidth: 1.2)
        )
    }

    private func hudMetric(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
            Text(sub)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
