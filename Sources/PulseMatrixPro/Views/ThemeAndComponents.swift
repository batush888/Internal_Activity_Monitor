import SwiftUI
import AppKit
import PulseMatrixCore

// MARK: - Liquid Glass Palette & Theme

public enum PulseTheme {
    public static let background = Color(red: 0.04, green: 0.06, blue: 0.11)
    public static let cardBackground = Color(red: 0.08, green: 0.11, blue: 0.19)
    public static let cardElevated = Color(red: 0.11, green: 0.15, blue: 0.25)
    public static let border = Color.white.opacity(0.14)
    public static let cyanAccent = Color(red: 0.22, green: 0.78, blue: 0.98)
    public static let emerald = Color(red: 0.10, green: 0.82, blue: 0.58)
    public static let amber = Color(red: 0.98, green: 0.65, blue: 0.12)
    public static let coral = Color(red: 0.96, green: 0.31, blue: 0.36)
    public static let purple = Color(red: 0.70, green: 0.40, blue: 0.98)
    public static let indigo = Color(red: 0.42, green: 0.48, blue: 0.98)

    public static func color(for severity: InsightSeverity) -> Color {
        switch severity {
        case .optimal: return emerald
        case .advisory: return cyanAccent
        case .warning: return amber
        case .critical: return coral
        }
    }

    public static func tempColor(_ celsius: Double) -> Color {
        if celsius >= 88.0 { return coral }
        if celsius >= 72.0 { return amber }
        if celsius >= 55.0 { return cyanAccent }
        return emerald
    }

    public static func percentageColor(_ pct: Double) -> Color {
        if pct >= 88.0 { return coral }
        if pct >= 70.0 { return amber }
        return cyanAccent
    }
}

// MARK: - Native macOS Behind-Window Liquid Glass Backdrop (Desktop Bleed-Through)

public struct LiquidGlassWindowBackdrop: NSViewRepresentable {
    public let glassIntensity: Double

    public init(glassIntensity: Double) {
        self.glassIntensity = glassIntensity
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = true

        DispatchQueue.main.async {
            if let window = view.window {
                configureWindow(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = glassIntensity < 0.45 ? .underWindowBackground : .hudWindow
        nsView.alphaValue = CGFloat(max(0.25, min(1.0, glassIntensity + 0.15)))
        if let window = nsView.window {
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        if window.isOpaque {
            window.isOpaque = false
        }
        if window.backgroundColor != .clear {
            window.backgroundColor = .clear
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

// MARK: - Liquid Glass Curated Card Component

public struct GlassCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let symbol: String?
    let badgeText: String?
    let accentColor: Color
    let glassIntensity: Double
    let content: Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        badgeText: String? = nil,
        accentColor: Color = PulseTheme.cyanAccent,
        glassIntensity: Double = 0.65,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.badgeText = badgeText
        self.accentColor = accentColor
        self.glassIntensity = glassIntensity
        self.content = content()
    }

    public var body: some View {
        let tintOpacity = max(0.18, min(0.88, glassIntensity * 0.78))
        let rimOpacity = max(0.18, min(0.55, (1.0 - glassIntensity * 0.35) * 0.45))

        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(alignment: .center, spacing: 10) {
                    if let symbol {
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.18))
                                .frame(width: 28, height: 28)
                            Image(systemName: symbol)
                                .foregroundStyle(accentColor)
                                .font(.system(size: 13.5, weight: .bold))
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }
                    Spacer()
                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.16))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
            content
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                PulseTheme.cardBackground.opacity(tintOpacity),
                                PulseTheme.background.opacity(min(0.92, tintOpacity + 0.12))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // Specular Liquid Glass Top Refraction Sheen
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10 * (1.15 - glassIntensity * 0.5)),
                                accentColor.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(rimOpacity),
                            accentColor.opacity(0.28),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Stacked Composition Bar (Multi-Layered Segmented Bar + Legend)

public struct CompositionSegment: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let valueText: String
    public let proportion: Double // 0.0 ... 1.0
    public let color: Color

    public init(label: String, valueText: String, proportion: Double, color: Color) {
        self.label = label
        self.valueText = valueText
        self.proportion = max(0.0, proportion)
        self.color = color
    }
}

public struct StackedCompositionBar: View {
    public let segments: [CompositionSegment]
    public let barHeight: CGFloat

    public init(segments: [CompositionSegment], barHeight: CGFloat = 14) {
        self.segments = segments
        self.barHeight = barHeight
    }

    public var body: some View {
        let totalProp = max(0.0001, segments.reduce(0.0) { $0 + $1.proportion })

        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(segments) { seg in
                        let widthRatio = CGFloat(seg.proportion / totalProp)
                        let segWidth = max(4.0, (geo.size.width - CGFloat(max(0, segments.count - 1) * 3)) * widthRatio)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [seg.color, seg.color.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: segWidth, height: barHeight)
                    }
                }
            }
            .frame(height: barHeight)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            )

            // Cleanly blocked segment legend
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(segments) { seg in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(seg.color)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(seg.label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                            Text(seg.valueText)
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Human-Centric Inline Plain-English Callout Pill

public struct InlineInsightCallout: View {
    public let title: String
    public let detail: String
    public let severity: InsightSeverity

    public init(title: String, detail: String, severity: InsightSeverity) {
        self.title = title
        self.detail = detail
        self.severity = severity
    }

    public var body: some View {
        let accent = PulseTheme.color(for: severity)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: severity == .optimal ? "checkmark.seal.fill" : (severity == .advisory ? "sparkles" : "exclamationmark.triangle.fill"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(accent.opacity(0.32), lineWidth: 1)
        )
    }
}

// MARK: - Compact Per-Core P-Core / E-Core Grid (Curated Visual Matrix)

public struct PerCoreMiniGrid: View {
    public let cores: [CoreLoad]
    public let columnsCount: Int

    public init(cores: [CoreLoad], columnsCount: Int = 5) {
        self.cores = cores
        self.columnsCount = columnsCount
    }

    public var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(2, columnsCount))
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(cores) { core in
                let isECore = core.cluster == .efficiency
                let baseColor = isECore ? PulseTheme.emerald : PulseTheme.cyanAccent
                let barColor = core.totalUsagePercent >= 88.0 ? PulseTheme.coral : baseColor

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text(isECore ? "E\(core.coreIndex + 1)" : "P\(core.coreIndex + 1)")
                            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(baseColor)
                        Spacer()
                        Text(String(format: "%.0f%%", core.totalUsagePercent))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(barColor)
                                .frame(width: max(3, geo.size.width * CGFloat(min(1.0, core.totalUsagePercent / 100.0))))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(baseColor.opacity(0.24), lineWidth: 0.8)
                )
            }
        }
    }
}

// MARK: - Circular Ring Gauge

public struct CircularMetricGauge: View {
    public let title: String
    public let valueText: String
    public let subtitle: String
    public let progress: Double // 0...100
    public let color: Color
    public var diameter: CGFloat = 84

    public init(
        title: String,
        valueText: String,
        subtitle: String,
        progress: Double,
        color: Color,
        diameter: CGFloat = 84
    ) {
        self.title = title
        self.valueText = valueText
        self.subtitle = subtitle
        self.progress = progress
        self.color = color
        self.diameter = diameter
    }

    public var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.09), lineWidth: 8.5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1.0, max(0.02, progress / 100.0))))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.65), color]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.35), radius: 5)

                VStack(spacing: 1) {
                    Text(valueText)
                        .font(.system(size: diameter > 90 ? 20 : 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(width: diameter, height: diameter)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Full Causal Insight Card

public struct InsightCardView: View {
    public let insight: SystemInsight
    public let onAction: (InsightRemediationAction) -> Void

    public init(insight: SystemInsight, onAction: @escaping (InsightRemediationAction) -> Void) {
        self.insight = insight
        self.onAction = onAction
    }

    public var body: some View {
        let badgeColor = PulseTheme.color(for: insight.severity)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(insight.severity.rawValue.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.2))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())

                Text(insight.category.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))

                Text("• \(insight.ruleIdentifier)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                Text(insight.rootCauseMetric)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(badgeColor)
            }

            Text(insight.headline)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(insight.plainEnglishNarrative)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            if !insight.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(insight.actions) { action in
                        Button {
                            onAction(action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.shield.fill")
                                    .font(.system(size: 11))
                                Text(action.label)
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(badgeColor.opacity(0.18))
                            .foregroundStyle(badgeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(badgeColor.opacity(0.35), lineWidth: 1)
        )
    }
}
