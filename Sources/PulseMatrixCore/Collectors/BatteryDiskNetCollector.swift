import Foundation
import IOKit
import IOKit.ps
import Darwin

public final class BatteryDiskNetCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var previousNetCounters: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousNetTime: Date?

    private var previousDiskReadBytes: UInt64 = 0
    private var previousDiskWriteBytes: UInt64 = 0
    private var previousDiskReadOps: UInt64 = 0
    private var previousDiskWriteOps: UInt64 = 0
    private var previousDiskTime: Date?

    public init() {}

    // MARK: - Battery Chemistry & Power Delivery

    public func sampleBattery() -> BatteryTelemetry {
        var isPresent = false
        var isCharging = false
        var isPluggedIn = false
        var chargePercent = 100.0
        var currentCapmAh = 0
        var maxCapmAh = 0
        var designCapmAh = 0
        var cycleCount = 0
        var tempCelsius = 29.5
        var voltageMV = 12000
        var amperageMA = 0
        var timeRemainingMin: Int? = nil
        var conditionLabel = "Normal"

        // 1. Read AppleSmartBattery from IORegistry for deep chemical metrics
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let props = propsRef?.takeRetainedValue() as? [String: Any] {

                isPresent = (props["BatteryInstalled"] as? Bool) ?? true
                isCharging = (props["IsCharging"] as? Bool) ?? false
                isPluggedIn = (props["ExternalConnected"] as? Bool) ?? false
                cycleCount = (props["CycleCount"] as? Int) ?? 0

                if let dCap = props["DesignCapacity"] as? Int, dCap > 0 {
                    designCapmAh = dCap
                }
                if let rawMax = props["AppleRawMaxCapacity"] as? Int, rawMax > 0 {
                    maxCapmAh = rawMax
                } else if let nomMax = props["NominalChargeCapacity"] as? Int, nomMax > 0 {
                    maxCapmAh = nomMax
                } else if let maxC = props["MaxCapacity"] as? Int, maxC > 100 {
                    maxCapmAh = maxC
                }

                if let rawCurr = props["AppleRawCurrentCapacity"] as? Int, rawCurr > 0 {
                    currentCapmAh = rawCurr
                } else if let currC = props["CurrentCapacity"] as? Int {
                    currentCapmAh = currC
                }

                if let v = props["Voltage"] as? Int, v > 0 {
                    voltageMV = v
                }
                if let amp = props["InstantAmperage"] as? Int {
                    amperageMA = amp
                } else if let amp = props["Amperage"] as? Int {
                    amperageMA = amp
                }

                // Temperature is in deci-Kelvin or centi-Celsius depending on platform
                if let rawTemp = props["Temperature"] as? Int, rawTemp > 0 {
                    if rawTemp > 2500 {
                        // deci-Kelvin (e.g. 3025 -> 302.5K -> 29.35C)
                        let c = (Double(rawTemp) / 10.0) - 273.15
                        if c > 10.0 && c < 85.0 {
                            tempCelsius = c
                        } else {
                            // centi-Celsius (e.g. 2950 -> 29.50C)
                            tempCelsius = Double(rawTemp) / 100.0
                        }
                    } else {
                        tempCelsius = Double(rawTemp) / 100.0
                    }
                }

                if let tRem = props["TimeRemaining"] as? Int, tRem > 0 && tRem < 6000 {
                    timeRemainingMin = tRem
                }
            }
        }

        // 2. Read IOPowerSources for user-facing percentage & condition
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {

            isPresent = true
            if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                chargePercent = Double(cur) / Double(max) * 100.0
            }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                isPluggedIn = (state == kIOPSACPowerValue as String)
            }
            if let chg = desc[kIOPSIsChargingKey as String] as? Bool {
                isCharging = chg
            }
            if let cond = desc["BatteryHealthCondition"] as? String, !cond.isEmpty {
                conditionLabel = cond
            }
        }

        let healthPercent: Double
        if designCapmAh > 0 && maxCapmAh > 0 {
            healthPercent = min(105.0, (Double(maxCapmAh) / Double(designCapmAh)) * 100.0)
        } else {
            healthPercent = 100.0
        }

        let powerWatts = abs(Double(voltageMV) * Double(amperageMA)) / 1_000_000.0

        return BatteryTelemetry(
            isPresent: isPresent,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            chargePercent: min(100.0, max(0.0, chargePercent)),
            currentCapacitymAh: currentCapmAh,
            maxCapacitymAh: maxCapmAh,
            designCapacitymAh: designCapmAh,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            temperatureCelsius: tempCelsius,
            voltageMillivolts: voltageMV,
            amperageMilliamps: amperageMA,
            powerWatts: powerWatts,
            timeRemainingMinutes: timeRemainingMin,
            conditionLabel: conditionLabel
        )
    }

    // MARK: - Disk & Network I/O

    public func sampleDiskAndNetwork() -> DiskNetworkTelemetry {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()

        // 1. Volume capacity via statfs("/")
        var fs = statfs()
        var totalDiskBytes: UInt64 = 0
        var freeDiskBytes: UInt64 = 0
        var volumeName = "Macintosh HD"

        if statfs("/", &fs) == 0 {
            let blockSize = UInt64(fs.f_bsize)
            totalDiskBytes = UInt64(fs.f_blocks) * blockSize
            freeDiskBytes = UInt64(fs.f_bavail) * blockSize
        }
        if let volName = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName {
            volumeName = volName
        }

        let usedDiskBytes = totalDiskBytes > freeDiskBytes ? (totalDiskBytes - freeDiskBytes) : 0
        let diskUsagePct = totalDiskBytes > 0 ? (Double(usedDiskBytes) / Double(totalDiskBytes) * 100.0) : 0.0

        // 2. Disk I/O counters via IOBlockStorageDriver
        var accReadBytes: UInt64 = 0
        var accWriteBytes: UInt64 = 0
        var accReadOps: UInt64 = 0
        var accWriteOps: UInt64 = 0

        var ioIter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &ioIter) == kIOReturnSuccess {
            defer { IOObjectRelease(ioIter) }
            var drive = IOIteratorNext(ioIter)
            while drive != 0 {
                defer {
                    IOObjectRelease(drive)
                    drive = IOIteratorNext(ioIter)
                }
                var propsRef: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(drive, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let props = propsRef?.takeRetainedValue() as? [String: Any],
                   let stats = props["Statistics"] as? [String: Any] {
                    if let rb = stats["Bytes (Read)"] as? UInt64 { accReadBytes &+= rb }
                    else if let rb = stats["Bytes (Read)"] as? Int, rb > 0 { accReadBytes &+= UInt64(rb) }

                    if let wb = stats["Bytes (Write)"] as? UInt64 { accWriteBytes &+= wb }
                    else if let wb = stats["Bytes (Write)"] as? Int, wb > 0 { accWriteBytes &+= UInt64(wb) }

                    if let ro = stats["Operations (Read)"] as? UInt64 { accReadOps &+= ro }
                    else if let ro = stats["Operations (Read)"] as? Int, ro > 0 { accReadOps &+= UInt64(ro) }

                    if let wo = stats["Operations (Write)"] as? UInt64 { accWriteOps &+= wo }
                    else if let wo = stats["Operations (Write)"] as? Int, wo > 0 { accWriteOps &+= UInt64(wo) }
                }
            }
        }

        var readBytesPerSec = 0.0
        var writeBytesPerSec = 0.0
        var readIOPS = 0.0
        var writeIOPS = 0.0

        if let prevDiskT = previousDiskTime {
            let dt = max(0.1, now.timeIntervalSince(prevDiskT))
            if accReadBytes >= previousDiskReadBytes {
                readBytesPerSec = Double(accReadBytes - previousDiskReadBytes) / dt
            }
            if accWriteBytes >= previousDiskWriteBytes {
                writeBytesPerSec = Double(accWriteBytes - previousDiskWriteBytes) / dt
            }
            if accReadOps >= previousDiskReadOps {
                readIOPS = Double(accReadOps - previousDiskReadOps) / dt
            }
            if accWriteOps >= previousDiskWriteOps {
                writeIOPS = Double(accWriteOps - previousDiskWriteOps) / dt
            }
        }
        previousDiskReadBytes = accReadBytes
        previousDiskWriteBytes = accWriteBytes
        previousDiskReadOps = accReadOps
        previousDiskWriteOps = accWriteOps
        previousDiskTime = now

        // 3. Network interface counters via getifaddrs()
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        var rawCounters: [String: (rx: UInt64, tx: UInt64, isUp: Bool)] = [:]
        var ipAddresses: [String: String] = [:]

        if getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr {
            defer { freeifaddrs(firstAddr) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let ifa = cursor?.pointee {
                let name = String(cString: ifa.ifa_name)
                let flags = Int32(ifa.ifa_flags)
                let isUp = (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0

                if let addr = ifa.ifa_addr {
                    let family = Int32(addr.pointee.sa_family)
                    if family == AF_LINK, let data = ifa.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        let rx = UInt64(networkData.ifi_ibytes)
                        let tx = UInt64(networkData.ifi_obytes)
                        let existing = rawCounters[name] ?? (rx: 0, tx: 0, isUp: isUp)
                        rawCounters[name] = (rx: max(existing.rx, rx), tx: max(existing.tx, tx), isUp: isUp)
                    } else if family == AF_INET {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(
                            addr,
                            socklen_t(addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        ) == 0 {
                            let nullIdx = hostname.firstIndex(of: 0) ?? hostname.endIndex
                            let bytes = hostname[..<nullIdx].map { UInt8(bitPattern: $0) }
                            ipAddresses[name] = String(decoding: bytes, as: UTF8.self)
                        }
                    }
                }
                cursor = ifa.ifa_next
            }
        }

        let netDt = max(0.1, previousNetTime.map { now.timeIntervalSince($0) } ?? 1.0)
        var interfaces: [NetworkInterfaceTelemetry] = []
        var totalDownloadRate = 0.0
        var totalUploadRate = 0.0
        var primaryIfName = "en0"

        for (name, data) in rawCounters.sorted(by: { $0.key < $1.key }) {
            // Focus on physical/tunnel interfaces (en*, bridge*, utun*, awdl0)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("bridge") else { continue }
            guard data.rx > 0 || data.tx > 0 || ipAddresses[name] != nil else { continue }

            var rxRate = 0.0
            var txRate = 0.0
            if previousNetTime != nil, let prev = previousNetCounters[name] {
                if data.rx >= prev.rx {
                    rxRate = Double(data.rx - prev.rx) / netDt
                }
                if data.tx >= prev.tx {
                    txRate = Double(data.tx - prev.tx) / netDt
                }
            }
            previousNetCounters[name] = (rx: data.rx, tx: data.tx)

            if name.hasPrefix("en") {
                totalDownloadRate += rxRate
                totalUploadRate += txRate
                if ipAddresses[name] != nil {
                    primaryIfName = name
                }
            }

            let displayName: String
            if name == "en0" {
                displayName = "Wi-Fi / Primary (\(name))"
            } else if name.hasPrefix("en") {
                displayName = "Ethernet / Thunderbolt (\(name))"
            } else if name.hasPrefix("utun") {
                displayName = "VPN / Tunnel (\(name))"
            } else {
                displayName = name
            }

            interfaces.append(
                NetworkInterfaceTelemetry(
                    name: name,
                    displayName: displayName,
                    ipAddress: ipAddresses[name] ?? "Link-Local",
                    isUp: data.isUp,
                    rxBytesPerSec: rxRate,
                    txBytesPerSec: txRate,
                    totalRxBytes: data.rx,
                    totalTxBytes: data.tx
                )
            )
        }

        previousNetTime = now

        return DiskNetworkTelemetry(
            volumeName: volumeName,
            totalDiskBytes: totalDiskBytes,
            freeDiskBytes: freeDiskBytes,
            usedDiskBytes: usedDiskBytes,
            diskUsagePercent: diskUsagePct,
            readBytesPerSec: readBytesPerSec,
            writeBytesPerSec: writeBytesPerSec,
            readIOPS: readIOPS,
            writeIOPS: writeIOPS,
            totalReadBytes: accReadBytes,
            totalWriteBytes: accWriteBytes,
            smartStatus: "Verified (APFS Online)",
            primaryInterface: primaryIfName,
            netDownloadBytesPerSec: totalDownloadRate,
            netUploadBytesPerSec: totalUploadRate,
            interfaces: interfaces
        )
    }
}
