import Foundation

public final class PrivilegedPowermetricsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var latestPrivilegedSample: PrivilegedPowerTelemetry?
    private var isAuthorizedSession = false

    public init() {}

    /// Attempts to run a single non-interactive `sudo -n powermetrics` sample first,
    /// or uses macOS Administrator authentication (`osascript`) when explicitly requested by user.
    public func requestPrivilegedSample(interactivePrompt: Bool) -> (telemetry: PrivilegedPowerTelemetry?, error: String?) {
        // 1. Try non-interactive sudo first (works if sudo timestamp is active or running as root)
        if let sample = runNonInteractiveSudoPowermetrics() {
            lock.lock()
            latestPrivilegedSample = sample
            isAuthorizedSession = true
            lock.unlock()
            return (sample, nil)
        }

        guard interactivePrompt else {
            return (nil, "Privileged powermetrics requires administrator authorization.")
        }

        // 2. Prompt via standard macOS Security Agent using osascript administrator privileges
        let script = """
        do shell script "/usr/bin/powermetrics --samplers cpu_power,gpu_power,ane_power,thermal --format plist -n 1 -i 400" with administrator privileges
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return (nil, "Failed to launch macOS authorization dialog: \(error.localizedDescription)")
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        if proc.terminationStatus == 0, let parsed = Self.parsePowermetricsPlist(data) {
            lock.lock()
            latestPrivilegedSample = parsed
            isAuthorizedSession = true
            lock.unlock()
            return (parsed, nil)
        } else {
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Authorization canceled."
            return (nil, errMsg)
        }
    }

    public func currentOrEstimatedPower(
        cpu: CPUTelemetry,
        gpu: GPUTelemetry,
        battery: BatteryTelemetry,
        thermal: SystemThermalStateLevel
    ) -> PrivilegedPowerTelemetry {
        lock.lock()
        let cached = latestPrivilegedSample
        let authorized = isAuthorizedSession
        lock.unlock()

        if authorized, let cached, Date().timeIntervalSince(cached.lastUpdated) < 15.0 {
            if let refreshed = runNonInteractiveSudoPowermetrics() {
                lock.lock()
                latestPrivilegedSample = refreshed
                lock.unlock()
                return refreshed
            }
            return cached
        }

        // Calibrated Apple M1 Max Silicon Power & Frequency Estimator (User-Space Mode)
        let eUtil = cpu.efficiencyClusterUsagePercent / 100.0
        let pUtil = cpu.performanceClusterUsagePercent / 100.0
        let gpuUtil = gpu.deviceUtilizationPercent / 100.0

        // M1 Max E-cluster: 600 MHz idle -> 2064 MHz boost
        let eFreq = 600.0 + (eUtil * 1464.0)
        // M1 Max P-cluster: 600 MHz idle -> 3228 MHz boost
        let pFreq = 600.0 + (pUtil * 2628.0)
        // M1 Max 32-core GPU: 389 MHz idle -> 1296 MHz boost
        let gpuFreq = 389.0 + (gpuUtil * 907.0)

        let cpuW = 0.45 + (eUtil * 1.35) + (pow(pUtil, 1.35) * 24.5)
        let gpuW = 0.25 + (pow(gpuUtil, 1.4) * 38.0)
        let dramW = 0.35 + ((eUtil + pUtil + gpuUtil) / 3.0) * 3.8
        let aneW = 0.05
        let pkgW = battery.powerWatts > 1.5 && !battery.isCharging
            ? max(cpuW + gpuW + dramW, battery.powerWatts * 0.72)
            : (cpuW + gpuW + dramW + aneW)

        return PrivilegedPowerTelemetry(
            isActive: false,
            cpuPowerWatts: cpuW,
            gpuPowerWatts: gpuW,
            anePowerWatts: aneW,
            dramPowerWatts: dramW,
            packagePowerWatts: pkgW,
            eClusterFreqMHz: eFreq,
            pClusterFreqMHz: pFreq,
            gpuFreqMHz: gpuFreq,
            thermalPressureLabel: thermal.rawValue,
            lastUpdated: Date()
        )
    }

    private func runNonInteractiveSudoPowermetrics() -> PrivilegedPowerTelemetry? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/powermetrics", "--samplers", "cpu_power,gpu_power,ane_power,thermal", "--format", "plist", "-n", "1", "-i", "250"]

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
        return Self.parsePowermetricsPlist(data)
    }

    public static func parsePowermetricsPlist(_ data: Data) -> PrivilegedPowerTelemetry? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let thermalPressure = (plist["thermal_pressure"] as? String) ?? "Nominal"
        var cpuMW = 0.0
        var gpuMW = 0.0
        var aneMW = 0.0
        var dramMW = 0.0
        var pkgMW = 0.0
        var eFreqMHz = 1020.0
        var pFreqMHz = 1800.0
        var gpuFreqMHz = 600.0

        if let processor = plist["processor"] as? [String: Any] {
            if let c = processor["cpu_power"] as? Double { cpuMW = c }
            else if let c = processor["cpu_energy"] as? Double { cpuMW = c }

            if let g = processor["gpu_power"] as? Double { gpuMW = g }
            else if let g = processor["gpu_energy"] as? Double { gpuMW = g }

            if let a = processor["ane_power"] as? Double { aneMW = a }
            else if let a = processor["ane_energy"] as? Double { aneMW = a }

            if let d = processor["dram_power"] as? Double { dramMW = d }
            if let p = processor["combined_power"] as? Double { pkgMW = p }

            if let clusters = processor["clusters"] as? [[String: Any]] {
                for cluster in clusters {
                    let name = (cluster["name"] as? String ?? "").uppercased()
                    let freqHz = (cluster["freq_hz"] as? Double) ?? 0.0
                    let freqMHz = freqHz > 10_000 ? (freqHz / 1_000_000.0) : freqHz
                    if name.hasPrefix("E") && freqMHz > 0 {
                        eFreqMHz = freqMHz
                    } else if name.hasPrefix("P") && freqMHz > 0 {
                        pFreqMHz = max(pFreqMHz, freqMHz)
                    }
                }
            }
        }

        if let gpuDict = plist["gpu"] as? [String: Any] {
            if let gPower = gpuDict["gpu_power"] as? Double, gpuMW == 0 {
                gpuMW = gPower
            }
            if let gFreq = gpuDict["freq_hz"] as? Double {
                gpuFreqMHz = gFreq > 10_000 ? (gFreq / 1_000_000.0) : gFreq
            }
        }

        let cpuW = cpuMW / 1000.0
        let gpuW = gpuMW / 1000.0
        let aneW = aneMW / 1000.0
        let dramW = dramMW / 1000.0
        let totalW = pkgMW > 0 ? (pkgMW / 1000.0) : (cpuW + gpuW + aneW + dramW)

        return PrivilegedPowerTelemetry(
            isActive: true,
            cpuPowerWatts: cpuW,
            gpuPowerWatts: gpuW,
            anePowerWatts: aneW,
            dramPowerWatts: dramW,
            packagePowerWatts: totalW,
            eClusterFreqMHz: eFreqMHz,
            pClusterFreqMHz: pFreqMHz,
            gpuFreqMHz: gpuFreqMHz,
            thermalPressureLabel: thermalPressure,
            lastUpdated: Date()
        )
    }
}
