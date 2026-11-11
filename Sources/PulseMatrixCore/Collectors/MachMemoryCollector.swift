import Foundation
import Darwin

public final class MachMemoryCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPageins: UInt64 = 0
    private var lastPageouts: UInt64 = 0
    private var lastSampleTime: Date?

    public let totalMemoryBytes: UInt64

    public init() {
        self.totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
    }

    public func sample() -> MemoryTelemetry {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        var pageSize: vm_size_t = 16384
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)

        var wiredBytes: UInt64 = 0
        var activeBytes: UInt64 = 0
        var compressedBytes: UInt64 = 0
        var purgeableBytes: UInt64 = 0
        var externalBytes: UInt64 = 0
        var internalBytes: UInt64 = 0
        var freePageBytes: UInt64 = 0
        var uncompressedInCompressorBytes: UInt64 = 0
        var pageinsRate = 0.0
        var pageoutsRate = 0.0

        if kr == KERN_SUCCESS {
            wiredBytes = UInt64(vmStats.wire_count) * pageBytes
            activeBytes = UInt64(vmStats.active_count) * pageBytes
            compressedBytes = UInt64(vmStats.compressor_page_count) * pageBytes
            purgeableBytes = UInt64(vmStats.purgeable_count) * pageBytes
            externalBytes = UInt64(vmStats.external_page_count) * pageBytes
            internalBytes = UInt64(vmStats.internal_page_count) * pageBytes
            freePageBytes = UInt64(vmStats.free_count) * pageBytes
            uncompressedInCompressorBytes = UInt64(vmStats.total_uncompressed_pages_in_compressor) * pageBytes

            let currPageins = UInt64(vmStats.pageins)
            let currPageouts = UInt64(vmStats.pageouts)

            if let prevTime = lastSampleTime {
                let dt = max(0.1, now.timeIntervalSince(prevTime))
                let dIn = currPageins >= lastPageins ? (currPageins - lastPageins) : 0
                let dOut = currPageouts >= lastPageouts ? (currPageouts - lastPageouts) : 0
                pageinsRate = Double(dIn) / dt
                pageoutsRate = Double(dOut) / dt
            }
            lastPageins = currPageins
            lastPageouts = currPageouts
            lastSampleTime = now
        }

        // Activity Monitor formula for App Memory: internal_page_count - purgeable_count
        let appMemoryBytes: UInt64
        if internalBytes > purgeableBytes {
            appMemoryBytes = internalBytes - purgeableBytes
        } else {
            appMemoryBytes = activeBytes
        }

        let cachedFilesBytes = externalBytes + purgeableBytes
        let rawUsedBytes = appMemoryBytes + wiredBytes + compressedBytes
        let usedBytes = min(totalMemoryBytes, rawUsedBytes)
        let freeBytes = totalMemoryBytes > usedBytes ? (totalMemoryBytes - usedBytes) : freePageBytes

        let compressionRatio: Double
        if compressedBytes > 0 && uncompressedInCompressorBytes >= compressedBytes {
            compressionRatio = Double(uncompressedInCompressorBytes) / Double(compressedBytes)
        } else {
            compressionRatio = 1.0
        }

        // Read swap usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsedBytes: UInt64 = 0
        var swapTotalBytes: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsedBytes = swapUsage.xsu_used
            swapTotalBytes = swapUsage.xsu_total
        }

        // Read kernel memory pressure level (1 = Normal, 2 = Warn, 4 = Critical)
        var pressureRaw: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureRaw, &pressureSize, nil, 0)

        let usagePercent = Double(usedBytes) / Double(max(1, totalMemoryBytes)) * 100.0

        let pressureLevel: MemoryPressureLevel
        if pressureRaw >= 4 || usagePercent >= 92.0 {
            pressureLevel = .critical
        } else if pressureRaw == 2 || usagePercent >= 80.0 || pageoutsRate > 25.0 {
            pressureLevel = .warning
        } else {
            pressureLevel = .nominal
        }

        return MemoryTelemetry(
            totalBytes: totalMemoryBytes,
            usedBytes: usedBytes,
            appMemoryBytes: appMemoryBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedFilesBytes: cachedFilesBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsedBytes,
            swapTotalBytes: swapTotalBytes,
            pageinsPerSec: pageinsRate,
            pageoutsPerSec: pageoutsRate,
            compressionRatio: compressionRatio,
            usagePercent: usagePercent,
            pressureLevel: pressureLevel
        )
    }
}
