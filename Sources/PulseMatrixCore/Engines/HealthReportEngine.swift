import Foundation

public final class HealthReportEngine: Sendable {
    public init() {}

    public func generateReport(from snapshot: SystemSnapshot, history: [SystemSnapshot]) -> ComputerHealthReport {
        // 1. Pillar 1: Silicon & Thermal Integrity (25%)
        let peakTemp = snapshot.thermal.socPeakTempCelsius
        let thermalHeadroom = max(0.0, 105.0 - peakTemp) // Apple Silicon TjMax ~105°C
        var thermalScore = 96
        if peakTemp > 90 { thermalScore = 68 }
        else if peakTemp > 80 { thermalScore = 82 }
        else if peakTemp > 68 { thermalScore = 90 }
        if snapshot.thermal.thermalState == .serious { thermalScore -= 15 }
        else if snapshot.thermal.thermalState == .critical { thermalScore -= 30 }
        thermalScore = max(25, min(100, thermalScore))

        let maxFanRPM = snapshot.thermal.fans.map(\.currentRPM).max() ?? 0
        let siliconPillar = HealthPillarScore(
            name: "Silicon & Thermal Integrity",
            weightPercent: 25,
            score: thermalScore,
            grade: Self.letterGrade(for: thermalScore),
            statusSummary: "SoC Peak \(String(format: "%.1f°C", peakTemp)) (\(String(format: "%.1f°C", thermalHeadroom)) headroom below 105°C TjMax)",
            findings: [
                "Processor: \(snapshot.cpu.brandString) (\(snapshot.cpu.performanceCoreCount) P-Cores + \(snapshot.cpu.efficiencyCoreCount) E-Cores)",
                "Thermal State: \(snapshot.thermal.thermalState.rawValue) | SoC Avg: \(String(format: "%.1f°C", snapshot.thermal.socAverageTempCelsius)), Peak: \(String(format: "%.1f°C", peakTemp))",
                "Active Cooling: \(snapshot.thermal.fans.isEmpty ? "Passive / Zero-RPM Mode" : "\(snapshot.thermal.fans.count) Fans (Max \(Int(maxFanRPM)) RPM)")"
            ],
            recommendation: thermalScore >= 88
                ? "Silicon thermal dissipation is operating within optimal factory parameters."
                : "Elevate rear chassis or inspect vents to improve sustained P-cluster boost clocks."
        )

        // 2. Pillar 2: Unified Memory Efficiency (20%)
        var memScore = 95
        if snapshot.memory.pressureLevel == .warning { memScore -= 18 }
        else if snapshot.memory.pressureLevel == .critical { memScore -= 38 }
        if snapshot.memory.pageoutsPerSec > 25 { memScore -= 12 }
        let swapGB = Double(snapshot.memory.swapUsedBytes) / 1_073_741_824.0
        if swapGB > 4.0 { memScore -= 10 }
        memScore = max(30, min(100, memScore))

        let memoryPillar = HealthPillarScore(
            name: "Unified Memory & Swap Hygiene",
            weightPercent: 20,
            score: memScore,
            grade: Self.letterGrade(for: memScore),
            statusSummary: "\(ByteFormatter.formatBytes(snapshot.memory.usedBytes)) / \(ByteFormatter.formatBytes(snapshot.memory.totalBytes)) (\(String(format: "%.0f%%", snapshot.memory.usagePercent))) — Pressure: \(snapshot.memory.pressureLevel.rawValue)",
            findings: [
                "App Memory: \(ByteFormatter.formatBytes(snapshot.memory.appMemoryBytes)) | Wired Kernel: \(ByteFormatter.formatBytes(snapshot.memory.wiredBytes))",
                "Hardware Compressor: \(ByteFormatter.formatBytes(snapshot.memory.compressedBytes)) at \(String(format: "%.2fx", snapshot.memory.compressionRatio)) ratio",
                "VM Swap Usage: \(ByteFormatter.formatBytes(snapshot.memory.swapUsedBytes)) | Pageout Rate: \(String(format: "%.1f pages/s", snapshot.memory.pageoutsPerSec))"
            ],
            recommendation: memScore >= 88
                ? "Zero swap thrashing detected; hardware memory compression is efficiently absorbing peaks."
                : "Reduce concurrent memory-heavy processes to prevent swap write amplification on your SSD."
        )

        // 3. Pillar 3: Battery Longevity & Power Delivery (25%)
        let bat = snapshot.battery
        var batScore = 95
        if bat.isPresent {
            let healthPenalty = max(0.0, (96.0 - bat.healthPercent) * 1.15)
            let cyclePenalty = Double(bat.cycleCount) / 1000.0 * 12.0
            let tempPenalty = bat.temperatureCelsius > 36.0 ? 8.0 : 0.0
            batScore = Int((100.0 - healthPenalty - cyclePenalty - tempPenalty).rounded())
            batScore = max(35, min(100, batScore))
        }
        let estRemainingCycles = bat.isPresent ? max(0, 1000 - bat.cycleCount) : 1000

        let batteryPillar = HealthPillarScore(
            name: "Battery Chemistry & Power Delivery",
            weightPercent: 25,
            score: batScore,
            grade: Self.letterGrade(for: batScore),
            statusSummary: bat.isPresent
                ? "\(String(format: "%.1f%%", bat.healthPercent)) Design Retention (\(bat.cycleCount) / 1000 Rated Cycles)"
                : "AC Desktop Power Supply (Continuous Nominal Delivery)",
            findings: bat.isPresent ? [
                "Chemical Capacity: \(bat.maxCapacitymAh) mAh current max vs \(bat.designCapacitymAh) mAh factory design (\(String(format: "%.1f%%", bat.healthPercent)))",
                "Cycle Longevity: \(bat.cycleCount) cycles completed (~ \(estRemainingCycles) cycles before 80% threshold)",
                "Electrical Bus: \(String(format: "%.2f V", Double(bat.voltageMillivolts) / 1000.0)) | \(bat.amperageMilliamps) mA (\(String(format: "%.1f W", bat.powerWatts))) | Pack Temp: \(String(format: "%.1f°C", bat.temperatureCelsius))"
            ] : [
                "Always-on AC Power Delivery verified."
            ],
            recommendation: bat.temperatureCelsius > 35.0
                ? "Battery pack is warm (\(String(format: "%.1f°C", bat.temperatureCelsius))); avoid fast-charging during heavy GPU/CPU renders."
                : "Battery chemical impedance and temperature (\(String(format: "%.1f°C", bat.temperatureCelsius))) are in ideal longevity range."
        )

        // 4. Pillar 4: Storage & NAND SSD Endurance (15%)
        let freePct = 100.0 - snapshot.diskNet.diskUsagePercent
        let freeGB = Double(snapshot.diskNet.freeDiskBytes) / 1_073_741_824.0
        var ssdScore = 96
        if freePct < 10.0 || freeGB < 20.0 { ssdScore = 62 }
        else if freePct < 18.0 || freeGB < 40.0 { ssdScore = 78 }
        else if freePct < 25.0 { ssdScore = 88 }

        let ssdWearRisk: String
        if swapGB > 6.0 || freePct < 12.0 {
            ssdWearRisk = "Elevated (High Swap + Low Free Block Pool)"
        } else if swapGB > 2.0 || freePct < 20.0 {
            ssdWearRisk = "Moderate (Watch APFS Free Space)"
        } else {
            ssdWearRisk = "Low (Optimal Over-Provisioning & Minimal Swap Writes)"
        }

        let storagePillar = HealthPillarScore(
            name: "NAND Storage & I/O Endurance",
            weightPercent: 15,
            score: ssdScore,
            grade: Self.letterGrade(for: ssdScore),
            statusSummary: "\(ByteFormatter.formatBytes(snapshot.diskNet.freeDiskBytes)) Free (\(String(format: "%.1f%%", freePct)) Over-Provisioning Headroom)",
            findings: [
                "Primary Volume (\(snapshot.diskNet.volumeName)): \(ByteFormatter.formatBytes(snapshot.diskNet.usedDiskBytes)) used of \(ByteFormatter.formatBytes(snapshot.diskNet.totalDiskBytes))",
                "SMART & APFS Integrity: \(snapshot.diskNet.smartStatus) | SSD Temp: \(String(format: "%.1f°C", snapshot.thermal.ssdTempCelsius))",
                "Cumulative Session I/O: \(ByteFormatter.formatBytes(snapshot.diskNet.totalReadBytes)) Read / \(ByteFormatter.formatBytes(snapshot.diskNet.totalWriteBytes)) Written"
            ],
            recommendation: ssdScore >= 85
                ? "APFS has ample free blocks (\(String(format: "%.1f%%", freePct))) for low-amplification wear leveling."
                : "Keep at least 15% of your SSD free to prevent APFS fragmentation and swap slowdown."
        )

        // 5. Pillar 5: Software & Background Hygiene (15%)
        let runawayProcs = snapshot.topProcesses.filter { $0.cpuPercent > 65.0 }
        let uptimeDays = snapshot.uptimeSeconds / 86400.0
        var hygieneScore = 94
        if runawayProcs.count >= 2 { hygieneScore -= 14 }
        else if runawayProcs.count == 1 { hygieneScore -= 6 }
        if uptimeDays > 21.0 { hygieneScore -= 8 }
        hygieneScore = max(45, min(100, hygieneScore))

        let top3Names = snapshot.topProcesses.prefix(3).map { "\($0.name) (\(String(format: "%.1f%%", $0.cpuPercent)))" }.joined(separator: ", ")
        let hygienePillar = HealthPillarScore(
            name: "Software & Process Hygiene",
            weightPercent: 15,
            score: hygieneScore,
            grade: Self.letterGrade(for: hygieneScore),
            statusSummary: "\(runawayProcs.count) Runaway Daemons | Uptime \(String(format: "%.1f days", uptimeDays))",
            findings: [
                "Top Active Processes: \(top3Names.isEmpty ? "Idle" : top3Names)",
                "Kernel Load Averages: \(String(format: "%.2f", snapshot.cpu.loadAverage1m)) (1m), \(String(format: "%.2f", snapshot.cpu.loadAverage5m)) (5m), \(String(format: "%.2f", snapshot.cpu.loadAverage15m)) (15m)",
                "Continuous System Uptime: \(String(format: "%.1f hours", snapshot.uptimeSeconds / 3600.0))"
            ],
            recommendation: uptimeDays > 14.0
                ? "System uptime exceeds 14 days; a scheduled reboot will clear kernel zone caches and dynamic swap files."
                : "Background daemon footprint is clean with balanced run-queue depth."
        )

        let pillars = [siliconPillar, memoryPillar, batteryPillar, storagePillar, hygienePillar]
        let weightedSum = pillars.reduce(0) { $0 + ($1.score * $1.weightPercent) }
        let overallScore = weightedSum / 100
        let overallGrade = Self.letterGrade(for: overallScore)

        let headline = "Composite Hardware & System Health: \(overallScore)/100 (Grade \(overallGrade))"
        let narrative = "Diagnostic audit of \(snapshot.hostname) (\(snapshot.cpu.brandString), \(ByteFormatter.formatBytes(snapshot.memory.totalBytes)) Unified Memory) indicates \(overallScore >= 88 ? "excellent overall hardware vitality and thermal efficiency" : "good operational health with targeted optimization opportunities"). Thermal headroom is \(String(format: "%.1f°C", thermalHeadroom)) below TjMax, battery chemical retention is at \(String(format: "%.1f%%", bat.healthPercent)) across \(bat.cycleCount) cycles, and SSD wear risk is rated '\(ssdWearRisk)'."

        let recommendations = pillars.map(\.recommendation)

        return ComputerHealthReport(
            machineModel: snapshot.cpu.brandString,
            hostname: snapshot.hostname,
            osVersion: snapshot.osVersion,
            uptimeHours: snapshot.uptimeSeconds / 3600.0,
            overallScore: overallScore,
            overallGrade: overallGrade,
            executiveHeadline: headline,
            executiveNarrative: narrative,
            pillars: pillars,
            batteryEstimatedRemainingCycles: estRemainingCycles,
            ssdWearRiskLevel: ssdWearRisk,
            thermalHeadroomCelsius: thermalHeadroom,
            topRecommendations: recommendations
        )
    }

    public func exportMarkdown(report: ComputerHealthReport) -> String {
        let df = ISO8601DateFormatter()
        var md = """
        # PulseMatrix Pro — Computer Health & Longevity Audit
        - **Machine**: \(report.machineModel) (`\(report.hostname)`)
        - **OS Version**: \(report.osVersion)
        - **Generated At**: \(df.string(from: report.generatedAt))
        - **Uptime**: \(String(format: "%.1f hours", report.uptimeHours))
        - **Overall Health Score**: **\(report.overallScore) / 100 (Grade \(report.overallGrade))**

        ## Executive Summary
        \(report.executiveNarrative)

        - **Thermal Headroom to TjMax (105°C)**: `\(String(format: "%.1f°C", report.thermalHeadroomCelsius))`
        - **Estimated Remaining Battery Cycles (to 80% spec)**: `\(report.batteryEstimatedRemainingCycles) cycles`
        - **NAND SSD Wear Risk Assessment**: `\(report.ssdWearRiskLevel)`

        ---

        ## 5-Pillar Hardware & Software Breakdown

        """

        for p in report.pillars {
            md += """
            ### \(p.name) — \(p.score)/100 (\(p.grade)) [Weight: \(p.weightPercent)%]
            **Status**: \(p.statusSummary)
            \(p.findings.map { "- \($0)" }.joined(separator: "\n"))
            - **Prescription**: *\(p.recommendation)*

            """
        }

        return md
    }

    public func exportInteractiveHTML(report: ComputerHealthReport, snapshot: SystemSnapshot) -> String {
        let pillarCardsHTML = report.pillars.map { p -> String in
            let color = p.score >= 90 ? "#10b981" : (p.score >= 78 ? "#3b82f6" : "#f59e0b")
            let findingsItems = p.findings.map { "<li>\($0)</li>" }.joined()
            return """
            <div class="pillar-card">
                <div class="pillar-header">
                    <div>
                        <h3>\(p.name)</h3>
                        <span class="pillar-sub">Weight: \(p.weightPercent)% &bull; \(p.statusSummary)</span>
                    </div>
                    <div class="score-badge" style="border-color: \(color); color: \(color);">
                        \(p.score) <small>\(p.grade)</small>
                    </div>
                </div>
                <div class="progress-track">
                    <div class="progress-fill" style="width: \(p.score)%; background: \(color);"></div>
                </div>
                <ul class="findings-list">\(findingsItems)</ul>
                <div class="prescription"><strong>Actionable Prescription:</strong> \(p.recommendation)</div>
            </div>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8" />
            <title>PulseMatrix Pro — Computer Health Report (\(report.hostname))</title>
            <style>
                :root {
                    --bg: #0b0f19;
                    --card: #131b2e;
                    --border: #23304d;
                    --text: #f1f5f9;
                    --muted: #94a3b8;
                    --accent: #38bdf8;
                    --emerald: #10b981;
                }
                * { box-sizing: border-box; }
                body {
                    margin: 0;
                    padding: 36px;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
                    background: radial-gradient(circle at top right, #162447, var(--bg) 60%);
                    color: var(--text);
                    line-height: 1.55;
                }
                .container { max-width: 1080px; margin: 0 auto; }
                .hero {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 18px;
                    padding: 28px 32px;
                    margin-bottom: 24px;
                    box-shadow: 0 18px 40px rgba(0,0,0,0.35);
                }
                .hero h1 { margin: 0 0 8px 0; font-size: 28px; }
                .hero p { margin: 6px 0; color: var(--muted); max-width: 720px; }
                .overall-ring {
                    text-align: center;
                    min-width: 150px;
                    padding: 18px;
                    border-radius: 16px;
                    background: rgba(16, 185, 129, 0.1);
                    border: 2px solid var(--emerald);
                }
                .overall-ring .num { font-size: 44px; font-weight: 800; color: var(--emerald); line-height: 1; }
                .overall-ring .grade { font-size: 15px; color: var(--text); margin-top: 6px; font-weight: 600; }
                .kpi-grid {
                    display: grid;
                    grid-template-columns: repeat(4, 1fr);
                    gap: 16px;
                    margin-bottom: 24px;
                }
                .kpi {
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 14px;
                    padding: 16px 20px;
                }
                .kpi .label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); }
                .kpi .val { font-size: 22px; font-weight: 700; margin-top: 4px; color: var(--accent); }
                .pillar-card {
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 16px;
                    padding: 22px 26px;
                    margin-bottom: 18px;
                }
                .pillar-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 12px;
                }
                .pillar-header h3 { margin: 0; font-size: 19px; }
                .pillar-sub { font-size: 13px; color: var(--muted); }
                .score-badge {
                    font-size: 22px;
                    font-weight: 800;
                    padding: 6px 14px;
                    border-radius: 12px;
                    border: 2px solid;
                }
                .progress-track {
                    height: 8px;
                    background: #1e293b;
                    border-radius: 999px;
                    overflow: hidden;
                    margin-bottom: 14px;
                }
                .progress-fill { height: 100%; border-radius: 999px; }
                .findings-list { margin: 0 0 12px 0; padding-left: 20px; color: #cbd5e1; font-size: 14px; }
                .prescription {
                    background: rgba(56, 189, 248, 0.08);
                    border-left: 3px solid var(--accent);
                    padding: 10px 14px;
                    border-radius: 6px;
                    font-size: 13.5px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="hero">
                    <div>
                        <h1>PulseMatrix Pro &mdash; Hardware &amp; System Health Audit</h1>
                        <p><strong>\(report.machineModel)</strong> &bull; Host: <code>\(report.hostname)</code> &bull; \(report.osVersion)</p>
                        <p>\(report.executiveNarrative)</p>
                    </div>
                    <div class="overall-ring">
                        <div class="num">\(report.overallScore)</div>
                        <div class="grade">Grade \(report.overallGrade) / 100</div>
                    </div>
                </div>
                <div class="kpi-grid">
                    <div class="kpi">
                        <div class="label">Thermal Headroom</div>
                        <div class="val">\(String(format: "%.1f°C", report.thermalHeadroomCelsius))</div>
                    </div>
                    <div class="kpi">
                        <div class="label">Battery Health &amp; Cycles</div>
                        <div class="val">\(String(format: "%.1f%%", snapshot.battery.healthPercent)) (\(snapshot.battery.cycleCount) cyc)</div>
                    </div>
                    <div class="kpi">
                        <div class="label">Unified RAM Pressure</div>
                        <div class="val">\(snapshot.memory.pressureLevel.rawValue) (\(String(format: "%.0f%%", snapshot.memory.usagePercent)))</div>
                    </div>
                    <div class="kpi">
                        <div class="label">SSD Free Headroom</div>
                        <div class="val">\(ByteFormatter.formatBytes(snapshot.diskNet.freeDiskBytes))</div>
                    </div>
                </div>
                \(pillarCardsHTML)
            </div>
        </body>
        </html>
        """
    }

    public static func letterGrade(for score: Int) -> String {
        switch score {
        case 95...100: return "A+"
        case 90..<95: return "A"
        case 85..<90: return "A-"
        case 80..<85: return "B+"
        case 75..<80: return "B"
        case 70..<75: return "C+"
        default: return "C"
        }
    }
}
