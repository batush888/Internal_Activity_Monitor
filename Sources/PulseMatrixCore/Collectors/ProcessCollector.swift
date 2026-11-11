import Foundation
import Darwin
import CIOKitBridge

public final class ProcessCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var previousCPUTimesNs: [Int32: UInt64] = [:]
    private var previousSampleDate: Date?

    public init() {}

    public func sampleTopProcesses(limit: Int = 35) -> [ProcessEntry] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let maxProcs = 1024
        let rawBuffer = UnsafeMutablePointer<PMProcessRawInfo>.allocate(capacity: maxProcs)
        defer { rawBuffer.deallocate() }

        let count = Int(pm_read_all_processes(rawBuffer, Int32(maxProcs)))
        if count > 0 {
            let dtSeconds = max(0.05, previousSampleDate.map { now.timeIntervalSince($0) } ?? 0.5)
            let dtNanoseconds = dtSeconds * 1_000_000_000.0
            var nextCPUTimes: [Int32: UInt64] = [:]
            nextCPUTimes.reserveCapacity(count)

            var entries: [ProcessEntry] = []
            entries.reserveCapacity(count)

            let currentUser = NSUserName()
            let currentUID = getuid()

            for i in 0..<count {
                var item = rawBuffer[i]
                let pid = item.pid
                let totalNs = item.totalUserTimeNs &+ item.totalSystemTimeNs
                nextCPUTimes[pid] = totalNs

                let cpuPercent: Double
                if previousSampleDate != nil, let prevNs = previousCPUTimesNs[pid], totalNs >= prevNs {
                    let deltaNs = Double(totalNs - prevNs)
                    cpuPercent = min(1000.0, (deltaNs / dtNanoseconds) * 100.0)
                } else {
                    cpuPercent = 0.0
                }

                let name = withUnsafePointer(to: &item.name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: 64) { cStr in
                        String(cString: cStr)
                    }
                }
                let path = withUnsafePointer(to: &item.path) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: 256) { cStr in
                        String(cString: cStr)
                    }
                }

                let userLabel = (item.uid == currentUID) ? currentUser : (item.uid == 0 ? "root" : "uid:\(item.uid)")

                entries.append(
                    ProcessEntry(
                        pid: pid,
                        ppid: item.ppid,
                        name: name.isEmpty ? "pid-\(pid)" : name,
                        commandPath: path,
                        user: userLabel,
                        cpuPercent: cpuPercent,
                        memoryBytes: item.residentBytes,
                        stateCode: "R (\(item.threadCount)t)",
                        isNativeArm64: true
                    )
                )
            }

            previousCPUTimesNs = nextCPUTimes
            previousSampleDate = now

            entries.sort { lhs, rhs in
                if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.5 {
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                return lhs.memoryBytes > rhs.memoryBytes
            }

            return Array(entries.prefix(limit))
        }

        // Fallback to /bin/ps if libproc returned 0
        return sampleViaPS(limit: limit)
    }

    private func sampleViaPS(limit: Int) -> [ProcessEntry] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid=,pcpu=,rss=,state=,user=,comm="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var entries: [ProcessEntry] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let parts = line.split(maxSplits: 6, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
            guard parts.count >= 7,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }

            let cpuStr = String(parts[2]).replacingOccurrences(of: ",", with: ".")
            let cpuPct = Double(cpuStr) ?? 0.0
            let rssKB = UInt64(parts[3]) ?? 0
            let memBytes = rssKB * 1024
            let stateCode = String(parts[4])
            let user = String(parts[5])
            let fullCommand = String(parts[6])
            let name = URL(fileURLWithPath: fullCommand).lastPathComponent

            entries.append(
                ProcessEntry(
                    pid: pid,
                    ppid: ppid,
                    name: name.isEmpty ? fullCommand : name,
                    commandPath: fullCommand,
                    user: user,
                    cpuPercent: cpuPct,
                    memoryBytes: memBytes,
                    stateCode: stateCode,
                    isNativeArm64: true
                )
            )
        }

        entries.sort { lhs, rhs in
            if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.5 {
                return lhs.cpuPercent > rhs.cpuPercent
            }
            return lhs.memoryBytes > rhs.memoryBytes
        }
        return Array(entries.prefix(limit))
    }

    public func sendSignal(to pid: Int32, signal: Int32) -> (success: Bool, message: String) {
        guard pid > 1 else {
            return (false, "Cannot signal launchd or kernel task (PID \(pid)).")
        }
        let res = Darwin.kill(pid, signal)
        if res == 0 {
            let sigName = (signal == SIGKILL) ? "SIGKILL (Force Quit)" : "SIGTERM (Graceful Quit)"
            return (true, "Sent \(sigName) to PID \(pid).")
        } else {
            let errStr = String(cString: strerror(errno))
            return (false, "Failed to signal PID \(pid): \(errStr)")
        }
    }
}
