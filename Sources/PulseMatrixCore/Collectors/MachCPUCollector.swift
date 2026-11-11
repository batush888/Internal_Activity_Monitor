import Foundation
import Darwin

public final class MachCPUCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []

    public let brandString: String
    public let physicalCores: Int
    public let logicalCores: Int
    public let efficiencyCores: Int
    public let performanceCores: Int

    public init() {
        self.brandString = Self.readSysctlString("machdep.cpu.brand_string") ?? "Apple Silicon SoC"
        let phys = Self.readSysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        let logi = Self.readSysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        self.physicalCores = max(1, phys)
        self.logicalCores = max(1, logi)

        // On Apple Silicon:
        // hw.perflevel0 = Performance (P-Core)
        // hw.perflevel1 = Efficiency (E-Core)
        let pCores = Self.readSysctlInt("hw.perflevel0.physicalcpu") ?? 0
        let eCores = Self.readSysctlInt("hw.perflevel1.physicalcpu") ?? 0
        if pCores + eCores > 0 {
            self.performanceCores = pCores
            self.efficiencyCores = eCores
        } else {
            self.efficiencyCores = min(2, self.physicalCores)
            self.performanceCores = max(0, self.physicalCores - self.efficiencyCores)
        }
    }

    public func sample(eFreqMHz: Double? = nil, pFreqMHz: Double? = nil) -> CPUTelemetry {
        lock.lock()
        defer { lock.unlock() }

        var numCPUsU: natural_t = 0
        var cpuInfoPtr: processor_info_array_t?
        var numCPUInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfoPtr,
            &numCPUInfoCount
        )

        var currentTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []

        if kr == KERN_SUCCESS, let info = cpuInfoPtr {
            let count = Int(numCPUsU)
            currentTicks.reserveCapacity(count)
            for i in 0..<count {
                let base = i * Int(CPU_STATE_MAX)
                let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
                let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
                let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
                let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
                currentTicks.append((user: user, system: system, idle: idle, nice: nice))
            }
            let deallocSize = vm_size_t(numCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), deallocSize)
        }

        var perCoreLoads: [CoreLoad] = []
        var totalUserSum = 0.0
        var totalSysSum = 0.0
        var totalIdleSum = 0.0
        var eClusterSum = 0.0
        var eClusterCount = 0
        var pClusterSum = 0.0
        var pClusterCount = 0
        var maxSingleCore = 0.0
        var hottestCoreIdx = 0

        for i in 0..<currentTicks.count {
            let curr = currentTicks[i]
            let prev = (i < previousTicks.count) ? previousTicks[i] : (user: 0, system: 0, idle: 0, nice: 0)

            let dUser = curr.user >= prev.user ? (curr.user - prev.user) : curr.user
            let dSys = curr.system >= prev.system ? (curr.system - prev.system) : curr.system
            let dIdle = curr.idle >= prev.idle ? (curr.idle - prev.idle) : curr.idle
            let dNice = curr.nice >= prev.nice ? (curr.nice - prev.nice) : curr.nice

            let totalTicks = Double(dUser + dSys + dIdle + dNice)
            let userPct: Double
            let sysPct: Double
            let idlePct: Double
            let activePct: Double

            if totalTicks > 0 {
                userPct = Double(dUser + dNice) / totalTicks * 100.0
                sysPct = Double(dSys) / totalTicks * 100.0
                idlePct = Double(dIdle) / totalTicks * 100.0
                activePct = min(100.0, max(0.0, userPct + sysPct))
            } else {
                userPct = 0.0
                sysPct = 0.0
                idlePct = 100.0
                activePct = 0.0
            }

            // On Apple Silicon (M1/M2/M3/M4), E-cores are indexed first (0..<efficiencyCores)
            let cluster: CoreClusterType = (i < efficiencyCores) ? .efficiency : .performance

            let load = CoreLoad(
                coreIndex: i,
                cluster: cluster,
                totalUsagePercent: activePct,
                userPercent: userPct,
                systemPercent: sysPct,
                idlePercent: idlePct
            )
            perCoreLoads.append(load)

            totalUserSum += userPct
            totalSysSum += sysPct
            totalIdleSum += idlePct

            if cluster == .efficiency {
                eClusterSum += activePct
                eClusterCount += 1
            } else {
                pClusterSum += activePct
                pClusterCount += 1
            }

            if activePct >= maxSingleCore {
                maxSingleCore = activePct
                hottestCoreIdx = i
            }
        }

        previousTicks = currentTicks

        let coreDenom = Double(max(1, perCoreLoads.count))
        let avgUser = totalUserSum / coreDenom
        let avgSys = totalSysSum / coreDenom
        let avgIdle = totalIdleSum / coreDenom
        let avgTotal = min(100.0, max(0.0, avgUser + avgSys))
        let eAvg = eClusterCount > 0 ? (eClusterSum / Double(eClusterCount)) : 0.0
        let pAvg = pClusterCount > 0 ? (pClusterSum / Double(pClusterCount)) : avgTotal

        var loads = [Double](repeating: 0.0, count: 3)
        getloadavg(&loads, 3)

        return CPUTelemetry(
            brandString: brandString,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            efficiencyCoreCount: efficiencyCores,
            performanceCoreCount: performanceCores,
            totalUsagePercent: avgTotal,
            userPercent: avgUser,
            systemPercent: avgSys,
            idlePercent: avgIdle,
            efficiencyClusterUsagePercent: eAvg,
            performanceClusterUsagePercent: pAvg,
            maxSingleCorePercent: maxSingleCore,
            hottestCoreIndex: hottestCoreIdx,
            loadAverage1m: loads[0],
            loadAverage5m: loads[1],
            loadAverage15m: loads[2],
            perCoreLoads: perCoreLoads,
            eClusterFrequencyMHz: eFreqMHz,
            pClusterFrequencyMHz: pFreqMHz
        )
    }

    public static func readSysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let nullIdx = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<nullIdx].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func readSysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 {
            return Int(value)
        }
        var value32: Int32 = 0
        var size32 = MemoryLayout<Int32>.size
        if sysctlbyname(name, &value32, &size32, nil, 0) == 0 {
            return Int(value32)
        }
        return nil
    }
}
