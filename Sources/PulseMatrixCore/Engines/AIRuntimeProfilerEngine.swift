import Foundation
import CIOKitBridge

public final class AIRuntimeProfilerEngine: @unchecked Sendable {
    public init() {}

    public func profile(snapshot: SystemSnapshot) -> AIProfilerTelemetry {
        let maxProcs = 1024
        let rawBuffer = UnsafeMutablePointer<PMProcessRawInfo>.allocate(capacity: maxProcs)
        defer { rawBuffer.deallocate() }

        let count = Int(pm_read_all_processes(rawBuffer, Int32(maxProcs)))

        // Map PID -> CPU % from snapshot.topProcesses where available
        var cpuByPID: [Int32: Double] = [:]
        for p in snapshot.topProcesses {
            cpuByPID[p.pid] = p.cpuPercent
        }

        var detected: [AIRuntimeProcess] = []
        let argsBufferSize = 65536
        let argsBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: argsBufferSize)
        defer { argsBuffer.deallocate() }

        for i in 0..<count {
            var item = rawBuffer[i]
            let pid = item.pid
            let ppid = item.ppid
            let resBytes = item.residentBytes

            let name = withUnsafePointer(to: &item.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
            }
            let path = withUnsafePointer(to: &item.path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }

            let lower = (name + " " + path).lowercased()
            let isCandidate = lower.contains("llama")
                || lower.contains("ollama")
                || lower.contains("mlx")
                || lower.contains("lm studio")
                || lower.contains("lmstudio")
                || lower.contains("whisper")
                || lower.contains("vllm")
                || lower.contains("localai")
                || lower.contains("jan")
                || lower.contains("python")
                || lower.contains("codex")

            guard isCandidate else { continue }

            let bytesRead = Int(pm_read_process_args_env(pid, argsBuffer, Int32(argsBufferSize)))
            let tokens: [String]
            if bytesRead > 0 {
                let rawStr = String(cString: argsBuffer)
                tokens = rawStr.split(separator: "\n").map(String.init)
            } else {
                tokens = [path]
            }

            let cpuPct = cpuByPID[pid] ?? 0.0
            if let runtime = Self.parseArgsAndEnv(
                tokens: tokens,
                processName: name,
                executablePath: path,
                pid: pid,
                ppid: ppid,
                cpuPercent: cpuPct,
                residentBytes: resBytes
            ) {
                detected.append(runtime)
            }
        }

        detected.sort { lhs, rhs in
            if lhs.residentMemoryBytes != rhs.residentMemoryBytes {
                return lhs.residentMemoryBytes > rhs.residentMemoryBytes
            }
            return lhs.cpuPercent > rhs.cpuPercent
        }

        let totalAIMem = detected.reduce(UInt64(0)) { $0 + $1.residentMemoryBytes }
        let totalAICPU = detected.reduce(0.0) { $0 + $1.cpuPercent }
        let maxCtx = detected.compactMap { $0.contextWindowTokens ?? $0.envMaxContextTokens }.max() ?? 0

        let wiredStatus = evaluateWiredMemoryLimit(
            totalRAMBytes: snapshot.memory.totalBytes,
            metalRecommendedBytes: snapshot.gpu.recommendedMaxWorkingSetBytes,
            inUseVRAMBytes: snapshot.gpu.inUseSystemMemoryBytes
        )

        let summary: String
        if detected.isEmpty {
            summary = "No active local LLM or ML inference runtimes (`llama-server`, `ollama`, `MLX`, `PyTorch`) are currently loaded in Unified Memory. Metal GPU wired limit is set to \(ByteFormatter.formatBytes(wiredStatus.effectivePinnableBytes))."
        } else {
            let names = detected.prefix(3).map { "\($0.processName) (\(ByteFormatter.formatBytes($0.residentMemoryBytes)))" }.joined(separator: ", ")
            let ctxText = maxCtx > 0 ? " Max detected context window: \(maxCtx.formatted()) tokens." : ""
            summary = "Detected \(detected.count) active AI/ML runtime process(es) consuming \(ByteFormatter.formatBytes(totalAIMem)) Unified Memory and \(String(format: "%.1f%%", totalAICPU)) CPU: \(names).\(ctxText)"
        }

        return AIProfilerTelemetry(
            detectedRuntimes: detected,
            totalAIMemoryBytes: totalAIMem,
            totalAICPUPercent: totalAICPU,
            maxDetectedContextTokens: maxCtx,
            wiredLimitStatus: wiredStatus,
            plainEnglishSummary: summary
        )
    }

    public static func parseArgsAndEnv(
        tokens: [String],
        processName: String,
        executablePath: String,
        pid: Int32,
        ppid: Int32,
        cpuPercent: Double,
        residentBytes: UInt64
    ) -> AIRuntimeProcess? {
        let lowerName = processName.lowercased()
        let lowerPath = executablePath.lowercased()
        let joinedLower = tokens.joined(separator: " ").lowercased()

        // Filter out generic Python processes unless they are AI/ML/Server related or using >150MB RAM
        if lowerName.contains("python") {
            let isAIOrServerPython = joinedLower.contains("mlx")
                || joinedLower.contains("torch")
                || joinedLower.contains("transformers")
                || joinedLower.contains("llama")
                || joinedLower.contains("ollama")
                || joinedLower.contains("vllm")
                || joinedLower.contains("uvicorn")
                || joinedLower.contains("harmony_ai")
                || joinedLower.contains("codex")
                || joinedLower.contains("whisper")
                || residentBytes > 250 * 1024 * 1024
            if !isAIOrServerPython {
                return nil
            }
        }

        // Ignore small Electron helper processes unless main runtime
        if lowerName.contains("codex") && residentBytes < 150 * 1024 * 1024 {
            return nil
        }

        var runtimeFramework = "Local AI Runtime"
        if lowerName.contains("llama-server") || lowerPath.contains("llama-server") {
            runtimeFramework = "llama.cpp / Ollama Runner"
        } else if lowerName == "ollama" || lowerPath.hasSuffix("/ollama") {
            runtimeFramework = "Ollama Daemon"
        } else if lowerName.contains("Ollama") {
            runtimeFramework = "Ollama App Host"
        } else if joinedLower.contains("mlx") {
            runtimeFramework = "Apple MLX Framework"
        } else if joinedLower.contains("uvicorn") {
            runtimeFramework = "Python FastAPI / AI Server"
        } else if lowerName.contains("python") {
            runtimeFramework = "Python AI / ML Worker"
        } else if lowerName.contains("whisper") {
            runtimeFramework = "Whisper ASR Engine"
        } else if lowerName.contains("lm studio") || lowerPath.contains("lm studio") {
            runtimeFramework = "LM Studio Engine"
        } else if lowerName.contains("codex") {
            runtimeFramework = "Codex Agent Runtime"
        }

        var modelID = "Active Resident Model"
        var ctxTokens: Int? = nil
        var envCtxTokens: Int? = nil
        var hasDraft = false
        var hasMMProj = false
        var port: String? = nil
        var workingDir = ""

        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            if (tok == "--model" || tok == "-m") && (i + 1) < tokens.count {
                let rawModel = tokens[i + 1]
                let lastComp = URL(fileURLWithPath: rawModel).lastPathComponent
                if lastComp.hasPrefix("sha256-") && lastComp.count > 19 {
                    modelID = "Ollama Blob (\(lastComp.prefix(19))…)"
                } else {
                    modelID = lastComp
                }
                i += 1
            } else if (tok == "-c" || tok == "--ctx-size") && (i + 1) < tokens.count {
                if let val = Int(tokens[i + 1]), val > 0 {
                    ctxTokens = val
                }
                i += 1
            } else if tok == "--port" && (i + 1) < tokens.count {
                port = tokens[i + 1]
                i += 1
            } else if tok == "--spec-draft-model" {
                hasDraft = true
            } else if tok == "--mmproj" {
                hasMMProj = true
            } else if tok.hasPrefix("OLLAMA_CONTEXT_LENGTH=") {
                let valStr = String(tok.dropFirst("OLLAMA_CONTEXT_LENGTH=".count))
                if let val = Int(valStr), val > 0 {
                    envCtxTokens = val
                }
            } else if tok.hasPrefix("PWD=") {
                workingDir = String(tok.dropFirst(4))
            } else if tok == "serve" && runtimeFramework.contains("Ollama") {
                modelID = "Ollama API Server (127.0.0.1:11434)"
                if port == nil { port = "11434" }
            }
            i += 1
        }

        let effectiveCtx = ctxTokens ?? envCtxTokens ?? 0
        // Estimate KV-cache bytes: ~18 KB per token for typical GQA 7B-32B models, or bounded by resident memory
        let rawKVEstimate = UInt64(max(0, effectiveCtx)) * 18_432
        let estimatedKV = min(residentBytes / 2, rawKVEstimate)

        let advisory: String
        if effectiveCtx >= 65_536 {
            advisory = "Oversized Context Window (\(effectiveCtx.formatted()) tokens\(hasDraft ? " + Speculative Draft" : "")\(hasMMProj ? " + Vision MMProj" : "")): Allocating ~\(ByteFormatter.formatBytes(max(estimatedKV, 1_500_000_000))) for KV-cache alone. Lowering OLLAMA_CONTEXT_LENGTH / -c to 16,384 or 32,768 will reclaim Unified Memory and prevent SSD swap spillover."
        } else if effectiveCtx >= 16_384 {
            advisory = "Moderate Context Window (\(effectiveCtx.formatted()) tokens): Balanced KV-cache footprint (~\(ByteFormatter.formatBytes(estimatedKV)))."
        } else if residentBytes > 4 * 1024 * 1024 * 1024 {
            advisory = "Large resident model footprint (\(ByteFormatter.formatBytes(residentBytes))). Ensure Metal wired memory limit has sufficient headroom."
        } else {
            advisory = "Nominal AI runtime footprint (\(ByteFormatter.formatBytes(residentBytes)))."
        }

        return AIRuntimeProcess(
            pid: pid,
            ppid: ppid,
            runtimeFramework: runtimeFramework,
            processName: processName,
            executablePath: executablePath,
            workingDirectory: workingDir,
            modelIdentifier: modelID,
            contextWindowTokens: ctxTokens,
            envMaxContextTokens: envCtxTokens,
            hasSpeculativeDraftModel: hasDraft,
            hasMultimodalProjector: hasMMProj,
            listeningPort: port,
            cpuPercent: cpuPercent,
            residentMemoryBytes: residentBytes,
            estimatedKVCacheBytes: estimatedKV,
            contextRiskAdvisory: advisory
        )
    }

    public func evaluateWiredMemoryLimit(
        totalRAMBytes: UInt64,
        metalRecommendedBytes: UInt64,
        inUseVRAMBytes: UInt64
    ) -> WiredMemoryLimitStatus {
        let customMB = Int(pm_read_iogpu_wired_limit_mb())
        let totalMB = Int(totalRAMBytes / (1024 * 1024))
        let safe85MB = Int(Double(totalMB) * 0.85)
        let max90MB = Int(Double(totalMB) * 0.90)

        let defaultWorkingSet = metalRecommendedBytes > 0
            ? metalRecommendedBytes
            : UInt64(Double(totalRAMBytes) * 0.75)

        let effectiveBytes: UInt64 = customMB > 0
            ? UInt64(customMB) * 1024 * 1024
            : defaultWorkingSet

        let advice: String
        if customMB == 0 {
            advice = "macOS default Metal wired limit is active (\(ByteFormatter.formatBytes(effectiveBytes)), ~75% of your \(ByteFormatter.formatBytes(totalRAMBytes)) Unified Memory). Raising `iogpu.wired_limit_mb` to \(safe85MB) MB (85%) unlocks an extra \(ByteFormatter.formatBytes(UInt64(safe85MB) * 1024 * 1024 - effectiveBytes)) of zero-swap GPU VRAM for local LLMs."
        } else {
            advice = "Custom Metal wired limit `iogpu.wired_limit_mb=\(customMB)` (\(ByteFormatter.formatBytes(effectiveBytes))) is active."
        }

        return WiredMemoryLimitStatus(
            totalPhysicalRAMBytes: totalRAMBytes,
            metalRecommendedMaxWorkingSetBytes: defaultWorkingSet,
            customSysctlWiredLimitMB: customMB,
            effectivePinnableBytes: effectiveBytes,
            currentInUseVRAMBytes: inUseVRAMBytes,
            safe85PercentMB: safe85MB,
            max90PercentMB: max90MB,
            plainEnglishAdvice: advice
        )
    }

    public func applyWiredLimitMB(_ limitMB: Int) -> (success: Bool, message: String) {
        let script = """
        do shell script "/usr/sbin/sysctl -w iogpu.wired_limit_mb=\(max(0, limitMB))" with administrator privileges
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
            return (false, "Failed to invoke macOS authorization: \(error.localizedDescription)")
        }

        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            if limitMB == 0 {
                return (true, "Reset `iogpu.wired_limit_mb` to macOS default (0).")
            } else {
                return (true, "Set `iogpu.wired_limit_mb` to \(limitMB) MB.")
            }
        } else {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Canceled"
            return (false, "Could not set wired limit: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
