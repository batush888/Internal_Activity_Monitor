import Foundation
import Darwin

public final class PrometheusMetricsServer: @unchecked Sendable {
    private let lock = NSLock()
    private var serverSocket: Int32 = -1
    private var isRunningFlag: Bool = false
    private var boundPort: UInt16 = EnvConfig.shared.prometheusPort
    private var latestPrometheusPayload: String = "# PulseMatrix Pro initializing\n"
    private var latestJSONPayload: String = "{}"
    private var requestCount: Int = 0

    public init() {}

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunningFlag
    }

    public var port: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return boundPort
    }

    public var servedRequestsCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    public func updatePayloads(
        snapshot: SystemSnapshot,
        aiTelemetry: AIProfilerTelemetry,
        healthReport: ComputerHealthReport
    ) {
        let prom = Self.formatPrometheusMetrics(
            snapshot: snapshot,
            aiTelemetry: aiTelemetry,
            healthReport: healthReport
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json: String
        if let data = try? encoder.encode(snapshot),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "{}"
        }

        lock.lock()
        latestPrometheusPayload = prom
        latestJSONPayload = json
        lock.unlock()
    }

    public func start(preferredPort: UInt16 = EnvConfig.shared.prometheusPort) -> (started: Bool, actualPort: UInt16, message: String) {
        let host = EnvConfig.shared.prometheusHost
        lock.lock()
        if isRunningFlag {
            let p = boundPort
            lock.unlock()
            return (true, p, "Prometheus & JSON server already active on http://\(host):\(p)/metrics")
        }
        lock.unlock()

        let candidates: [UInt16] = [preferredPort, preferredPort + 1, preferredPort + 2, 9191]
        for candidatePort in candidates {
            let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }

            var yes: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = candidatePort.bigEndian
            addr.sin_addr.s_addr = inet_addr(host)

            let bindRes = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if bindRes == 0 && Darwin.listen(sock, 16) == 0 {
                lock.lock()
                self.serverSocket = sock
                self.boundPort = candidatePort
                self.isRunningFlag = true
                lock.unlock()

                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.acceptLoop(listenSocket: sock)
                }
                return (true, candidatePort, "Prometheus & JSON Exporter listening at http://\(host):\(candidatePort)/metrics")
            } else {
                Darwin.close(sock)
            }
        }

        return (false, preferredPort, "Could not bind \(host) port \(preferredPort) (sandbox or port in use).")
    }

    public func stop() {
        lock.lock()
        let sock = serverSocket
        serverSocket = -1
        isRunningFlag = false
        lock.unlock()

        if sock >= 0 {
            Darwin.close(sock)
        }
    }

    private func acceptLoop(listenSocket: Int32) {
        while true {
            lock.lock()
            let active = isRunningFlag && (serverSocket == listenSocket)
            lock.unlock()
            if !active { break }

            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSock = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(listenSocket, sockPtr, &clientLen)
                }
            }

            if clientSock < 0 {
                break
            }

            handleClient(socket: clientSock)
        }
    }

    private func handleClient(socket: Int32) {
        defer { Darwin.close(socket) }

        var reqBuf = [UInt8](repeating: 0, count: 2048)
        let bytesRead = Darwin.read(socket, &reqBuf, reqBuf.count - 1)
        let reqString = bytesRead > 0 ? String(decoding: reqBuf[..<bytesRead], as: UTF8.self) : "GET /metrics"

        lock.lock()
        requestCount += 1
        let prom = latestPrometheusPayload
        let json = latestJSONPayload
        lock.unlock()

        if let requiredKey = EnvConfig.shared.metricsAPIKey {
            let expectedHeader = "Authorization: Bearer \(requiredKey)"
            let expectedQuery = "api_key=\(requiredKey)"
            if !reqString.contains(expectedHeader) && !reqString.contains(expectedQuery) {
                let unauth = "HTTP/1.1 401 Unauthorized\r\nContent-Type: text/plain\r\nContent-Length: 12\r\nConnection: close\r\n\r\nUnauthorized"
                let unauthData = Data(unauth.utf8)
                unauthData.withUnsafeBytes { rawPtr in
                    if let base = rawPtr.baseAddress {
                        _ = Darwin.write(socket, base, unauthData.count)
                    }
                }
                return
            }
        }

        let isJSONEndpoint = reqString.contains("GET /api/v1/snapshot") || reqString.contains("GET /json")
        let body = isJSONEndpoint ? json : prom
        let contentType = isJSONEndpoint ? "application/json; charset=utf-8" : "text/plain; version=0.0.4; charset=utf-8"
        let bodyData = Data(body.utf8)

        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r

        """
        var responseData = Data(header.utf8)
        responseData.append(bodyData)

        responseData.withUnsafeBytes { rawPtr in
            if let base = rawPtr.baseAddress {
                _ = Darwin.write(socket, base, responseData.count)
            }
        }
    }

    public static func formatPrometheusMetrics(
        snapshot: SystemSnapshot,
        aiTelemetry: AIProfilerTelemetry,
        healthReport: ComputerHealthReport
    ) -> String {
        let pkgWatts = snapshot.thermal.privilegedPower?.packagePowerWatts ?? snapshot.battery.powerWatts
        let cpuWatts = snapshot.thermal.privilegedPower?.cpuPowerWatts ?? 0.0
        let gpuWatts = snapshot.thermal.privilegedPower?.gpuPowerWatts ?? 0.0
        let aneWatts = snapshot.thermal.privilegedPower?.anePowerWatts ?? 0.0

        var lines: [String] = [
            "# HELP pulsematrix_cpu_usage_percent Total CPU utilization percentage.",
            "# TYPE pulsematrix_cpu_usage_percent gauge",
            String(format: "pulsematrix_cpu_usage_percent{soc=\"%@\"} %.2f", snapshot.cpu.brandString, snapshot.cpu.totalUsagePercent),
            "# HELP pulsematrix_cpu_cluster_usage_percent Apple Silicon E-Cluster and P-Cluster utilization.",
            "# TYPE pulsematrix_cpu_cluster_usage_percent gauge",
            String(format: "pulsematrix_cpu_cluster_usage_percent{cluster=\"performance\"} %.2f", snapshot.cpu.performanceClusterUsagePercent),
            String(format: "pulsematrix_cpu_cluster_usage_percent{cluster=\"efficiency\"} %.2f", snapshot.cpu.efficiencyClusterUsagePercent),
            "# HELP pulsematrix_memory_bytes Unified Memory breakdown in bytes.",
            "# TYPE pulsematrix_memory_bytes gauge",
            "pulsematrix_memory_bytes{segment=\"total\"} \(snapshot.memory.totalBytes)",
            "pulsematrix_memory_bytes{segment=\"used\"} \(snapshot.memory.usedBytes)",
            "pulsematrix_memory_bytes{segment=\"app\"} \(snapshot.memory.appMemoryBytes)",
            "pulsematrix_memory_bytes{segment=\"wired\"} \(snapshot.memory.wiredBytes)",
            "pulsematrix_memory_bytes{segment=\"compressed\"} \(snapshot.memory.compressedBytes)",
            "pulsematrix_memory_bytes{segment=\"swap_used\"} \(snapshot.memory.swapUsedBytes)",
            "# HELP pulsematrix_gpu_utilization_percent Metal GPU utilization percentage.",
            "# TYPE pulsematrix_gpu_utilization_percent gauge",
            String(format: "pulsematrix_gpu_utilization_percent{model=\"%@\"} %.2f", snapshot.gpu.modelName, snapshot.gpu.deviceUtilizationPercent),
            "# HELP pulsematrix_gpu_vram_bytes Metal GPU Unified VRAM bytes.",
            "# TYPE pulsematrix_gpu_vram_bytes gauge",
            "pulsematrix_gpu_vram_bytes{type=\"in_use\"} \(snapshot.gpu.inUseSystemMemoryBytes)",
            "pulsematrix_gpu_vram_bytes{type=\"wired_limit\"} \(aiTelemetry.wiredLimitStatus.effectivePinnableBytes)",
            "# HELP pulsematrix_soc_temperature_celsius Apple Silicon SoC temperature in Celsius.",
            "# TYPE pulsematrix_soc_temperature_celsius gauge",
            String(format: "pulsematrix_soc_temperature_celsius{sensor=\"average\"} %.2f", snapshot.thermal.socAverageTempCelsius),
            String(format: "pulsematrix_soc_temperature_celsius{sensor=\"peak\"} %.2f", snapshot.thermal.socPeakTempCelsius),
            "# HELP pulsematrix_power_watts Silicon and system power draw in Watts.",
            "# TYPE pulsematrix_power_watts gauge",
            String(format: "pulsematrix_power_watts{domain=\"package\"} %.2f", pkgWatts),
            String(format: "pulsematrix_power_watts{domain=\"cpu\"} %.2f", cpuWatts),
            String(format: "pulsematrix_power_watts{domain=\"gpu\"} %.2f", gpuWatts),
            String(format: "pulsematrix_power_watts{domain=\"ane\"} %.2f", aneWatts),
            "# HELP pulsematrix_battery_percent Battery charge and chemical health percentages.",
            "# TYPE pulsematrix_battery_percent gauge",
            String(format: "pulsematrix_battery_percent{metric=\"charge\"} %.2f", snapshot.battery.chargePercent),
            String(format: "pulsematrix_battery_percent{metric=\"health\"} %.2f", snapshot.battery.healthPercent),
            "pulsematrix_battery_cycles_total \(snapshot.battery.cycleCount)",
            "# HELP pulsematrix_ai_runtime_metrics Local AI / LLM inference profiler metrics.",
            "# TYPE pulsematrix_ai_runtime_metrics gauge",
            "pulsematrix_ai_active_processes \(aiTelemetry.detectedRuntimes.count)",
            "pulsematrix_ai_resident_memory_bytes \(aiTelemetry.totalAIMemoryBytes)",
            "pulsematrix_ai_max_context_tokens \(aiTelemetry.maxDetectedContextTokens)",
            "# HELP pulsematrix_health_score Composite 0-100 hardware and software health score.",
            "# TYPE pulsematrix_health_score gauge",
            "pulsematrix_health_score \(healthReport.overallScore)"
        ]

        for rt in aiTelemetry.detectedRuntimes {
            let ctx = rt.contextWindowTokens ?? rt.envMaxContextTokens ?? 0
            lines.append(
                String(
                    format: "pulsematrix_ai_process_memory_bytes{pid=\"%d\",process=\"%@\",framework=\"%@\",context_tokens=\"%d\"} %llu",
                    rt.pid,
                    rt.processName,
                    rt.runtimeFramework,
                    ctx,
                    rt.residentMemoryBytes
                )
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
