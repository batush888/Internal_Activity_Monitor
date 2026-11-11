import Foundation

// MARK: - CPU Telemetry & Apple Silicon Topology

public enum CoreClusterType: String, Codable, Sendable, CaseIterable {
    case efficiency = "Efficiency (E-Core)"
    case performance = "Performance (P-Core)"
    case standard = "Standard Core"
}

public struct CoreLoad: Identifiable, Codable, Sendable, Equatable {
    public var id: Int { coreIndex }
    public let coreIndex: Int
    public let cluster: CoreClusterType
    public let totalUsagePercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double

    public init(
        coreIndex: Int,
        cluster: CoreClusterType,
        totalUsagePercent: Double,
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double
    ) {
        self.coreIndex = coreIndex
        self.cluster = cluster
        self.totalUsagePercent = totalUsagePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
    }
}

public struct CPUTelemetry: Codable, Sendable, Equatable {
    public let brandString: String
    public let physicalCores: Int
    public let logicalCores: Int
    public let efficiencyCoreCount: Int
    public let performanceCoreCount: Int
    public let totalUsagePercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let efficiencyClusterUsagePercent: Double
    public let performanceClusterUsagePercent: Double
    public let maxSingleCorePercent: Double
    public let hottestCoreIndex: Int
    public let loadAverage1m: Double
    public let loadAverage5m: Double
    public let loadAverage15m: Double
    public let perCoreLoads: [CoreLoad]
    public let eClusterFrequencyMHz: Double?
    public let pClusterFrequencyMHz: Double?

    public init(
        brandString: String,
        physicalCores: Int,
        logicalCores: Int,
        efficiencyCoreCount: Int,
        performanceCoreCount: Int,
        totalUsagePercent: Double,
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double,
        efficiencyClusterUsagePercent: Double,
        performanceClusterUsagePercent: Double,
        maxSingleCorePercent: Double,
        hottestCoreIndex: Int,
        loadAverage1m: Double,
        loadAverage5m: Double,
        loadAverage15m: Double,
        perCoreLoads: [CoreLoad],
        eClusterFrequencyMHz: Double? = nil,
        pClusterFrequencyMHz: Double? = nil
    ) {
        self.brandString = brandString
        self.physicalCores = physicalCores
        self.logicalCores = logicalCores
        self.efficiencyCoreCount = efficiencyCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.totalUsagePercent = totalUsagePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.efficiencyClusterUsagePercent = efficiencyClusterUsagePercent
        self.performanceClusterUsagePercent = performanceClusterUsagePercent
        self.maxSingleCorePercent = maxSingleCorePercent
        self.hottestCoreIndex = hottestCoreIndex
        self.loadAverage1m = loadAverage1m
        self.loadAverage5m = loadAverage5m
        self.loadAverage15m = loadAverage15m
        self.perCoreLoads = perCoreLoads
        self.eClusterFrequencyMHz = eClusterFrequencyMHz
        self.pClusterFrequencyMHz = pClusterFrequencyMHz
    }
}

// MARK: - Unified Memory Telemetry

public enum MemoryPressureLevel: String, Codable, Sendable, CaseIterable {
    case nominal = "Nominal"
    case warning = "Warning"
    case critical = "Critical"
}

public struct MemoryTelemetry: Codable, Sendable, Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let appMemoryBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedFilesBytes: UInt64
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pageinsPerSec: Double
    public let pageoutsPerSec: Double
    public let compressionRatio: Double
    public let usagePercent: Double
    public let pressureLevel: MemoryPressureLevel

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        appMemoryBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        cachedFilesBytes: UInt64,
        freeBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        pageinsPerSec: Double,
        pageoutsPerSec: Double,
        compressionRatio: Double,
        usagePercent: Double,
        pressureLevel: MemoryPressureLevel
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appMemoryBytes = appMemoryBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pageinsPerSec = pageinsPerSec
        self.pageoutsPerSec = pageoutsPerSec
        self.compressionRatio = compressionRatio
        self.usagePercent = usagePercent
        self.pressureLevel = pressureLevel
    }
}

// MARK: - GPU & Neural Engine Telemetry

public struct GPUTelemetry: Codable, Sendable, Equatable {
    public let modelName: String
    public let coreCount: Int
    public let deviceUtilizationPercent: Double
    public let rendererUtilizationPercent: Double
    public let tilerUtilizationPercent: Double
    public let inUseSystemMemoryBytes: UInt64
    public let allocatedSystemMemoryBytes: UInt64
    public let recommendedMaxWorkingSetBytes: UInt64
    public let anePowerWatts: Double?
    public let gpuFrequencyMHz: Double?

    public init(
        modelName: String,
        coreCount: Int,
        deviceUtilizationPercent: Double,
        rendererUtilizationPercent: Double,
        tilerUtilizationPercent: Double,
        inUseSystemMemoryBytes: UInt64,
        allocatedSystemMemoryBytes: UInt64,
        recommendedMaxWorkingSetBytes: UInt64,
        anePowerWatts: Double? = nil,
        gpuFrequencyMHz: Double? = nil
    ) {
        self.modelName = modelName
        self.coreCount = coreCount
        self.deviceUtilizationPercent = deviceUtilizationPercent
        self.rendererUtilizationPercent = rendererUtilizationPercent
        self.tilerUtilizationPercent = tilerUtilizationPercent
        self.inUseSystemMemoryBytes = inUseSystemMemoryBytes
        self.allocatedSystemMemoryBytes = allocatedSystemMemoryBytes
        self.recommendedMaxWorkingSetBytes = recommendedMaxWorkingSetBytes
        self.anePowerWatts = anePowerWatts
        self.gpuFrequencyMHz = gpuFrequencyMHz
    }
}

// MARK: - Thermal, Fan & Privileged Power Telemetry

public enum SystemThermalStateLevel: String, Codable, Sendable, CaseIterable {
    case nominal = "Nominal"
    case fair = "Fair (Warm)"
    case serious = "Serious (Throttling)"
    case critical = "Critical (Heavy Throttling)"
}

public struct ThermalSensorItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let temperatureCelsius: Double

    public init(name: String, temperatureCelsius: Double) {
        self.name = name
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct FanSensorItem: Identifiable, Codable, Sendable, Equatable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    public let currentRPM: Double
    public let minRPM: Double
    public let maxRPM: Double
    public var utilizationPercent: Double {
        guard maxRPM > minRPM else { return 0 }
        return max(0, min(100, ((currentRPM - minRPM) / (maxRPM - minRPM)) * 100.0))
    }

    public init(index: Int, name: String, currentRPM: Double, minRPM: Double, maxRPM: Double) {
        self.index = index
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public struct PrivilegedPowerTelemetry: Codable, Sendable, Equatable {
    public let isActive: Bool
    public let cpuPowerWatts: Double
    public let gpuPowerWatts: Double
    public let anePowerWatts: Double
    public let dramPowerWatts: Double
    public let packagePowerWatts: Double
    public let eClusterFreqMHz: Double
    public let pClusterFreqMHz: Double
    public let gpuFreqMHz: Double
    public let thermalPressureLabel: String
    public let lastUpdated: Date

    public init(
        isActive: Bool,
        cpuPowerWatts: Double,
        gpuPowerWatts: Double,
        anePowerWatts: Double,
        dramPowerWatts: Double,
        packagePowerWatts: Double,
        eClusterFreqMHz: Double,
        pClusterFreqMHz: Double,
        gpuFreqMHz: Double,
        thermalPressureLabel: String,
        lastUpdated: Date = Date()
    ) {
        self.isActive = isActive
        self.cpuPowerWatts = cpuPowerWatts
        self.gpuPowerWatts = gpuPowerWatts
        self.anePowerWatts = anePowerWatts
        self.dramPowerWatts = dramPowerWatts
        self.packagePowerWatts = packagePowerWatts
        self.eClusterFreqMHz = eClusterFreqMHz
        self.pClusterFreqMHz = pClusterFreqMHz
        self.gpuFreqMHz = gpuFreqMHz
        self.thermalPressureLabel = thermalPressureLabel
        self.lastUpdated = lastUpdated
    }
}

public struct ThermalFanTelemetry: Codable, Sendable, Equatable {
    public let thermalState: SystemThermalStateLevel
    public let socAverageTempCelsius: Double
    public let socPeakTempCelsius: Double
    public let cpuClusterTempCelsius: Double
    public let gpuClusterTempCelsius: Double
    public let batteryTempCelsius: Double
    public let ssdTempCelsius: Double
    public let sensors: [ThermalSensorItem]
    public let fans: [FanSensorItem]
    public let privilegedPower: PrivilegedPowerTelemetry?

    public init(
        thermalState: SystemThermalStateLevel,
        socAverageTempCelsius: Double,
        socPeakTempCelsius: Double,
        cpuClusterTempCelsius: Double,
        gpuClusterTempCelsius: Double,
        batteryTempCelsius: Double,
        ssdTempCelsius: Double,
        sensors: [ThermalSensorItem],
        fans: [FanSensorItem],
        privilegedPower: PrivilegedPowerTelemetry? = nil
    ) {
        self.thermalState = thermalState
        self.socAverageTempCelsius = socAverageTempCelsius
        self.socPeakTempCelsius = socPeakTempCelsius
        self.cpuClusterTempCelsius = cpuClusterTempCelsius
        self.gpuClusterTempCelsius = gpuClusterTempCelsius
        self.batteryTempCelsius = batteryTempCelsius
        self.ssdTempCelsius = ssdTempCelsius
        self.sensors = sensors
        self.fans = fans
        self.privilegedPower = privilegedPower
    }
}

// MARK: - Battery Telemetry

public struct BatteryTelemetry: Codable, Sendable, Equatable {
    public let isPresent: Bool
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let chargePercent: Double
    public let currentCapacitymAh: Int
    public let maxCapacitymAh: Int
    public let designCapacitymAh: Int
    public let healthPercent: Double
    public let cycleCount: Int
    public let temperatureCelsius: Double
    public let voltageMillivolts: Int
    public let amperageMilliamps: Int
    public let powerWatts: Double
    public let timeRemainingMinutes: Int?
    public let conditionLabel: String

    public init(
        isPresent: Bool,
        isCharging: Bool,
        isPluggedIn: Bool,
        chargePercent: Double,
        currentCapacitymAh: Int,
        maxCapacitymAh: Int,
        designCapacitymAh: Int,
        healthPercent: Double,
        cycleCount: Int,
        temperatureCelsius: Double,
        voltageMillivolts: Int,
        amperageMilliamps: Int,
        powerWatts: Double,
        timeRemainingMinutes: Int?,
        conditionLabel: String
    ) {
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.chargePercent = chargePercent
        self.currentCapacitymAh = currentCapacitymAh
        self.maxCapacitymAh = maxCapacitymAh
        self.designCapacitymAh = designCapacitymAh
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.powerWatts = powerWatts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.conditionLabel = conditionLabel
    }
}

// MARK: - Disk & Network Telemetry

public struct NetworkInterfaceTelemetry: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let ipAddress: String
    public let isUp: Bool
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64

    public init(
        name: String,
        displayName: String,
        ipAddress: String,
        isUp: Bool,
        rxBytesPerSec: Double,
        txBytesPerSec: Double,
        totalRxBytes: UInt64,
        totalTxBytes: UInt64
    ) {
        self.name = name
        self.displayName = displayName
        self.ipAddress = ipAddress
        self.isUp = isUp
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
        self.totalRxBytes = totalRxBytes
        self.totalTxBytes = totalTxBytes
    }
}

public struct DiskNetworkTelemetry: Codable, Sendable, Equatable {
    public let volumeName: String
    public let totalDiskBytes: UInt64
    public let freeDiskBytes: UInt64
    public let usedDiskBytes: UInt64
    public let diskUsagePercent: Double
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double
    public let readIOPS: Double
    public let writeIOPS: Double
    public let totalReadBytes: UInt64
    public let totalWriteBytes: UInt64
    public let smartStatus: String
    public let primaryInterface: String
    public let netDownloadBytesPerSec: Double
    public let netUploadBytesPerSec: Double
    public let interfaces: [NetworkInterfaceTelemetry]

    public init(
        volumeName: String,
        totalDiskBytes: UInt64,
        freeDiskBytes: UInt64,
        usedDiskBytes: UInt64,
        diskUsagePercent: Double,
        readBytesPerSec: Double,
        writeBytesPerSec: Double,
        readIOPS: Double,
        writeIOPS: Double,
        totalReadBytes: UInt64,
        totalWriteBytes: UInt64,
        smartStatus: String,
        primaryInterface: String,
        netDownloadBytesPerSec: Double,
        netUploadBytesPerSec: Double,
        interfaces: [NetworkInterfaceTelemetry]
    ) {
        self.volumeName = volumeName
        self.totalDiskBytes = totalDiskBytes
        self.freeDiskBytes = freeDiskBytes
        self.usedDiskBytes = usedDiskBytes
        self.diskUsagePercent = diskUsagePercent
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
        self.readIOPS = readIOPS
        self.writeIOPS = writeIOPS
        self.totalReadBytes = totalReadBytes
        self.totalWriteBytes = totalWriteBytes
        self.smartStatus = smartStatus
        self.primaryInterface = primaryInterface
        self.netDownloadBytesPerSec = netDownloadBytesPerSec
        self.netUploadBytesPerSec = netUploadBytesPerSec
        self.interfaces = interfaces
    }
}

// MARK: - Process Telemetry

public struct ProcessEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let name: String
    public let commandPath: String
    public let user: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let stateCode: String
    public let isNativeArm64: Bool
    public var energyImpactScore: Double {
        let memMB = Double(memoryBytes) / (1024.0 * 1024.0)
        return min(100.0, cpuPercent * 0.82 + min(18.0, memMB / 512.0))
    }

    public init(
        pid: Int32,
        ppid: Int32,
        name: String,
        commandPath: String,
        user: String,
        cpuPercent: Double,
        memoryBytes: UInt64,
        stateCode: String,
        isNativeArm64: Bool = true
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.commandPath = commandPath
        self.user = user
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.stateCode = stateCode
        self.isNativeArm64 = isNativeArm64
    }
}

// MARK: - Complete Point-in-Time System Snapshot

public struct SystemSnapshot: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let uptimeSeconds: TimeInterval
    public let hostname: String
    public let osVersion: String
    public let cpu: CPUTelemetry
    public let memory: MemoryTelemetry
    public let gpu: GPUTelemetry
    public let thermal: ThermalFanTelemetry
    public let battery: BatteryTelemetry
    public let diskNet: DiskNetworkTelemetry
    public let topProcesses: [ProcessEntry]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        uptimeSeconds: TimeInterval,
        hostname: String,
        osVersion: String,
        cpu: CPUTelemetry,
        memory: MemoryTelemetry,
        gpu: GPUTelemetry,
        thermal: ThermalFanTelemetry,
        battery: BatteryTelemetry,
        diskNet: DiskNetworkTelemetry,
        topProcesses: [ProcessEntry]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.uptimeSeconds = uptimeSeconds
        self.hostname = hostname
        self.osVersion = osVersion
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.thermal = thermal
        self.battery = battery
        self.diskNet = diskNet
        self.topProcesses = topProcesses
    }
}

// MARK: - Causal Insights Engine Models

public enum InsightSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case optimal = "Optimal"
    case advisory = "Advisory"
    case warning = "Warning"
    case critical = "Critical"

    private var rank: Int {
        switch self {
        case .optimal: return 0
        case .advisory: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum InsightCategory: String, Codable, Sendable, CaseIterable {
    case cpu = "Silicon & CPU"
    case memory = "Unified Memory"
    case thermal = "Thermal & Acoustics"
    case gpu = "GPU & Metal"
    case battery = "Battery & Power"
    case storage = "SSD & Storage"
    case network = "Network I/O"
    case anomaly = "Statistical Anomaly"
}

public enum InsightRemediationKind: String, Codable, Sendable, Equatable {
    case terminateProcessSIGKILL
    case terminateProcessSIGTERM
    case reclaimInactiveMemoryHint
    case startDiagnosticSession
    case copyDiagnosticPrescription
    case inspectProcessInTab
}

public struct InsightRemediationAction: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(kind.rawValue)-\(targetPID ?? 0)" }
    public let label: String
    public let kind: InsightRemediationKind
    public let targetPID: Int32?
    public let targetProcessName: String?
    public let commandPreview: String

    public init(
        label: String,
        kind: InsightRemediationKind,
        targetPID: Int32? = nil,
        targetProcessName: String? = nil,
        commandPreview: String = ""
    ) {
        self.label = label
        self.kind = kind
        self.targetPID = targetPID
        self.targetProcessName = targetProcessName
        self.commandPreview = commandPreview
    }
}

public struct SystemInsight: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let timestamp: Date
    public let severity: InsightSeverity
    public let category: InsightCategory
    public let ruleIdentifier: String
    public let headline: String
    public let plainEnglishNarrative: String
    public let rootCauseMetric: String
    public let zScoreAnomaly: Double?
    public let culpritProcess: ProcessEntry?
    public let actions: [InsightRemediationAction]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        severity: InsightSeverity,
        category: InsightCategory,
        ruleIdentifier: String,
        headline: String,
        plainEnglishNarrative: String,
        rootCauseMetric: String,
        zScoreAnomaly: Double? = nil,
        culpritProcess: ProcessEntry? = nil,
        actions: [InsightRemediationAction] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.category = category
        self.ruleIdentifier = ruleIdentifier
        self.headline = headline
        self.plainEnglishNarrative = plainEnglishNarrative
        self.rootCauseMetric = rootCauseMetric
        self.zScoreAnomaly = zScoreAnomaly
        self.culpritProcess = culpritProcess
        self.actions = actions
    }
}

// MARK: - Workload Session Recording & A/B Comparison Models

public struct SessionSamplePoint: Identifiable, Codable, Sendable, Equatable {
    public var id: Int { secondOffset }
    public let secondOffset: Int
    public let timestamp: Date
    public let cpuTotalPercent: Double
    public let pClusterPercent: Double
    public let eClusterPercent: Double
    public let maxSingleCorePercent: Double
    public let memoryUsedBytes: UInt64
    public let memoryCompressedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let gpuUtilizationPercent: Double
    public let socTempCelsius: Double
    public let fanMaxRPM: Double
    public let packageWatts: Double
    public let diskReadBytesPerSec: Double
    public let diskWriteBytesPerSec: Double
    public let netRxBytesPerSec: Double
    public let netTxBytesPerSec: Double
    public let topProcessName: String
    public let topProcessCPUPercent: Double
}

public struct PerformanceSessionReport: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var workloadTag: String
    public let startTime: Date
    public let endTime: Date
    public let durationSeconds: Int
    public let sampleCount: Int
    public let avgCPUPercent: Double
    public let peakCPUPercent: Double
    public let p95CPUPercent: Double
    public let p99CPUPercent: Double
    public let onePercentLowStabilityScore: Double
    public let avgGPUUtilizationPercent: Double
    public let peakGPUUtilizationPercent: Double
    public let avgMemoryUsedBytes: UInt64
    public let peakMemoryUsedBytes: UInt64
    public let peakSwapUsedBytes: UInt64
    public let avgSoCTempCelsius: Double
    public let peakSoCTempCelsius: Double
    public let secondsToThermalWarning: Int?
    public let avgPowerWatts: Double
    public let estimatedWattHours: Double
    public let dominantProcessName: String
    public let executiveSummary: String
    public let samples: [SessionSamplePoint]
}

public struct SessionABComparison: Sendable, Equatable {
    public let baseline: PerformanceSessionReport
    public let candidate: PerformanceSessionReport
    public let cpuAvgDeltaPercent: Double
    public let gpuAvgDeltaPercent: Double
    public let peakTempDeltaCelsius: Double
    public let peakMemoryDeltaBytes: Int64
    public let stabilityScoreDelta: Double
    public let powerAvgDeltaWatts: Double
    public let plainEnglishVerdict: String
}

// MARK: - Computer Health & Hardware Longevity Report Models

public struct HealthPillarScore: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let weightPercent: Int
    public let score: Int // 0...100
    public let grade: String
    public let statusSummary: String
    public let findings: [String]
    public let recommendation: String

    public init(
        name: String,
        weightPercent: Int,
        score: Int,
        grade: String,
        statusSummary: String,
        findings: [String],
        recommendation: String
    ) {
        self.name = name
        self.weightPercent = weightPercent
        self.score = score
        self.grade = grade
        self.statusSummary = statusSummary
        self.findings = findings
        self.recommendation = recommendation
    }
}

public struct ComputerHealthReport: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let generatedAt: Date
    public let machineModel: String
    public let hostname: String
    public let osVersion: String
    public let uptimeHours: Double
    public let overallScore: Int // 0...100
    public let overallGrade: String
    public let executiveHeadline: String
    public let executiveNarrative: String
    public let pillars: [HealthPillarScore]
    public let batteryEstimatedRemainingCycles: Int
    public let ssdWearRiskLevel: String
    public let thermalHeadroomCelsius: Double
    public let topRecommendations: [String]

    public init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        machineModel: String,
        hostname: String,
        osVersion: String,
        uptimeHours: Double,
        overallScore: Int,
        overallGrade: String,
        executiveHeadline: String,
        executiveNarrative: String,
        pillars: [HealthPillarScore],
        batteryEstimatedRemainingCycles: Int,
        ssdWearRiskLevel: String,
        thermalHeadroomCelsius: Double,
        topRecommendations: [String]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.machineModel = machineModel
        self.hostname = hostname
        self.osVersion = osVersion
        self.uptimeHours = uptimeHours
        self.overallScore = overallScore
        self.overallGrade = overallGrade
        self.executiveHeadline = executiveHeadline
        self.executiveNarrative = executiveNarrative
        self.pillars = pillars
        self.batteryEstimatedRemainingCycles = batteryEstimatedRemainingCycles
        self.ssdWearRiskLevel = ssdWearRiskLevel
        self.thermalHeadroomCelsius = thermalHeadroomCelsius
        self.topRecommendations = topRecommendations
    }
}

// MARK: - Formatting Utilities

public enum ByteFormatter {
    public static func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        let tb = gb / 1024.0
        if tb >= 1.0 {
            return String(format: "%.2f TB", tb)
        } else if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.0f KB", kb)
        }
        return "\(bytes) B"
    }

    public static func formatRate(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        if gb >= 1.0 {
            return String(format: "%.2f GB/s", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        } else if kb >= 1.0 {
            return String(format: "%.1f KB/s", kb)
        }
        return String(format: "%.0f B/s", max(0, bytesPerSec))
    }
}


// MARK: - Local AI & LLM Inference Profiler Models (#3)

public struct AIRuntimeProcess: Identifiable, Codable, Sendable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let runtimeFramework: String
    public let processName: String
    public let executablePath: String
    public let workingDirectory: String
    public let modelIdentifier: String
    public let contextWindowTokens: Int?
    public let envMaxContextTokens: Int?
    public let hasSpeculativeDraftModel: Bool
    public let hasMultimodalProjector: Bool
    public let listeningPort: String?
    public let cpuPercent: Double
    public let residentMemoryBytes: UInt64
    public let estimatedKVCacheBytes: UInt64
    public let contextRiskAdvisory: String

    public init(
        pid: Int32,
        ppid: Int32,
        runtimeFramework: String,
        processName: String,
        executablePath: String,
        workingDirectory: String,
        modelIdentifier: String,
        contextWindowTokens: Int?,
        envMaxContextTokens: Int?,
        hasSpeculativeDraftModel: Bool,
        hasMultimodalProjector: Bool,
        listeningPort: String?,
        cpuPercent: Double,
        residentMemoryBytes: UInt64,
        estimatedKVCacheBytes: UInt64,
        contextRiskAdvisory: String
    ) {
        self.pid = pid
        self.ppid = ppid
        self.runtimeFramework = runtimeFramework
        self.processName = processName
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.modelIdentifier = modelIdentifier
        self.contextWindowTokens = contextWindowTokens
        self.envMaxContextTokens = envMaxContextTokens
        self.hasSpeculativeDraftModel = hasSpeculativeDraftModel
        self.hasMultimodalProjector = hasMultimodalProjector
        self.listeningPort = listeningPort
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
        self.estimatedKVCacheBytes = estimatedKVCacheBytes
        self.contextRiskAdvisory = contextRiskAdvisory
    }
}

public struct WiredMemoryLimitStatus: Codable, Sendable, Equatable {
    public let totalPhysicalRAMBytes: UInt64
    public let metalRecommendedMaxWorkingSetBytes: UInt64
    public let customSysctlWiredLimitMB: Int
    public let effectivePinnableBytes: UInt64
    public let currentInUseVRAMBytes: UInt64
    public let safe85PercentMB: Int
    public let max90PercentMB: Int
    public let plainEnglishAdvice: String

    public init(
        totalPhysicalRAMBytes: UInt64,
        metalRecommendedMaxWorkingSetBytes: UInt64,
        customSysctlWiredLimitMB: Int,
        effectivePinnableBytes: UInt64,
        currentInUseVRAMBytes: UInt64,
        safe85PercentMB: Int,
        max90PercentMB: Int,
        plainEnglishAdvice: String
    ) {
        self.totalPhysicalRAMBytes = totalPhysicalRAMBytes
        self.metalRecommendedMaxWorkingSetBytes = metalRecommendedMaxWorkingSetBytes
        self.customSysctlWiredLimitMB = customSysctlWiredLimitMB
        self.effectivePinnableBytes = effectivePinnableBytes
        self.currentInUseVRAMBytes = currentInUseVRAMBytes
        self.safe85PercentMB = safe85PercentMB
        self.max90PercentMB = max90PercentMB
        self.plainEnglishAdvice = plainEnglishAdvice
    }
}

public struct AIProfilerTelemetry: Codable, Sendable, Equatable {
    public let detectedRuntimes: [AIRuntimeProcess]
    public let totalAIMemoryBytes: UInt64
    public let totalAICPUPercent: Double
    public let maxDetectedContextTokens: Int
    public let wiredLimitStatus: WiredMemoryLimitStatus
    public let plainEnglishSummary: String

    public init(
        detectedRuntimes: [AIRuntimeProcess],
        totalAIMemoryBytes: UInt64,
        totalAICPUPercent: Double,
        maxDetectedContextTokens: Int,
        wiredLimitStatus: WiredMemoryLimitStatus,
        plainEnglishSummary: String
    ) {
        self.detectedRuntimes = detectedRuntimes
        self.totalAIMemoryBytes = totalAIMemoryBytes
        self.totalAICPUPercent = totalAICPUPercent
        self.maxDetectedContextTokens = maxDetectedContextTokens
        self.wiredLimitStatus = wiredLimitStatus
        self.plainEnglishSummary = plainEnglishSummary
    }
}

// MARK: - Menu Bar Sparklines, Floating HUD & Prometheus Config (#7)

public struct MenuBarCustomizationConfig: Codable, Sendable, Equatable {
    public var showMiniSparkline: Bool = true
    public var showCPU: Bool = true
    public var showRAM: Bool = true
    public var showGPU: Bool = false
    public var showTemp: Bool = true
    public var showWatts: Bool = true
    public var showAIBadge: Bool = true

    public init(
        showMiniSparkline: Bool = true,
        showCPU: Bool = true,
        showRAM: Bool = true,
        showGPU: Bool = false,
        showTemp: Bool = true,
        showWatts: Bool = true,
        showAIBadge: Bool = true
    ) {
        self.showMiniSparkline = showMiniSparkline
        self.showCPU = showCPU
        self.showRAM = showRAM
        self.showGPU = showGPU
        self.showTemp = showTemp
        self.showWatts = showWatts
        self.showAIBadge = showAIBadge
    }
}
