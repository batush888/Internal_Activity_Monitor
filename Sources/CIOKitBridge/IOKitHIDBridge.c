#include "IOKitHIDBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <mach/mach_time.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

// MARK: - Private IOHIDEventSystem Declarations for Apple Silicon Temperature Sensors

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

#define kIOHIDEventTypeTemperature 15
#define IOHIDEventFieldBase(type) (type << 16)
#define kIOHIDEventFieldTemperatureLevel IOHIDEventFieldBase(kIOHIDEventTypeTemperature)

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timeout);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

int pm_read_hid_thermal_sensors(PMThermalSensorReading *outReadings, int maxCount) {
    if (!outReadings || maxCount <= 0) {
        return 0;
    }

    int page = 0xff00;
    int usage = 0x0005;

    CFNumberRef pageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);

    const void *keys[2] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *values[2] = { pageNum, usageNum };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );

    CFRelease(pageNum);
    CFRelease(usageNum);

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!system) {
        CFRelease(matching);
        return 0;
    }

    IOHIDEventSystemClientSetMatching(system, matching);
    CFRelease(matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (!services) {
        CFRelease(system);
        return 0;
    }

    CFIndex serviceCount = CFArrayGetCount(services);
    int written = 0;

    for (CFIndex i = 0; i < serviceCount && written < maxCount; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (!service) continue;

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
        if (!event) continue;

        double temp = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel);
        CFRelease(event);

        if (temp <= 5.0 || temp >= 135.0) {
            continue;
        }

        char nameBuf[64] = "SoC Thermal Sensor";
        CFTypeRef productProp = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (productProp) {
            if (CFGetTypeID(productProp) == CFStringGetTypeID()) {
                CFStringGetCString((CFStringRef)productProp, nameBuf, sizeof(nameBuf), kCFStringEncodingUTF8);
            }
            CFRelease(productProp);
        }

        strncpy(outReadings[written].name, nameBuf, sizeof(outReadings[written].name) - 1);
        outReadings[written].name[sizeof(outReadings[written].name) - 1] = '\0';
        outReadings[written].valueCelsius = temp;
        written++;
    }

    CFRelease(services);
    CFRelease(system);
    return written;
}

// MARK: - AppleSMC User-Space Reader

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef unsigned char SMCBytes_t[32];

typedef struct {
    uint32_t key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static uint32_t smc_str_to_uint32(const char *str) {
    return ((uint32_t)(unsigned char)str[0] << 24) |
           ((uint32_t)(unsigned char)str[1] << 16) |
           ((uint32_t)(unsigned char)str[2] << 8)  |
           ((uint32_t)(unsigned char)str[3]);
}

static bool smc_read_key(io_connect_t conn, const char *keyStr, SMCKeyData_t *outVal) {
    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(SMCKeyData_t));
    memset(&output, 0, sizeof(SMCKeyData_t));

    input.key = smc_str_to_uint32(keyStr);
    input.data8 = SMC_CMD_READ_KEYINFO;

    size_t outSize = sizeof(SMCKeyData_t);
    kern_return_t kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &input, sizeof(SMCKeyData_t), &output, &outSize);
    if (kr != kIOReturnSuccess || output.keyInfo.dataSize == 0) {
        return false;
    }

    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;
    uint32_t dataType = output.keyInfo.dataType;

    outSize = sizeof(SMCKeyData_t);
    kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &input, sizeof(SMCKeyData_t), &output, &outSize);
    if (kr != kIOReturnSuccess) {
        return false;
    }

    output.keyInfo.dataType = dataType;
    output.keyInfo.dataSize = input.keyInfo.dataSize;
    *outVal = output;
    return true;
}

static double smc_decode_numeric(const SMCKeyData_t *val) {
    uint32_t type = val->keyInfo.dataType;
    uint32_t size = val->keyInfo.dataSize;
    const unsigned char *b = val->bytes;

    if (type == smc_str_to_uint32("flt ") && size == 4) {
        float f = 0.0f;
        memcpy(&f, b, sizeof(float));
        return (double)f;
    }
    if (type == smc_str_to_uint32("sp78") && size == 2) {
        int16_t raw = (int16_t)((b[0] << 8) | b[1]);
        return (double)raw / 256.0;
    }
    if (type == smc_str_to_uint32("fpe2") && size == 2) {
        uint16_t raw = (uint16_t)((b[0] << 8) | b[1]);
        return (double)raw / 4.0;
    }
    if (type == smc_str_to_uint32("ui8 ") && size == 1) {
        return (double)b[0];
    }
    if (type == smc_str_to_uint32("ui16") && size == 2) {
        return (double)((b[0] << 8) | b[1]);
    }
    return -1.0;
}

int pm_read_smc_fans(PMFanReading *outFans, int maxFans) {
    if (!outFans || maxFans <= 0) return 0;

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess || !conn) return 0;

    SMCKeyData_t numVal;
    int fanCount = 2;
    if (smc_read_key(conn, "FNum", &numVal)) {
        int n = (int)smc_decode_numeric(&numVal);
        if (n > 0 && n <= 6) fanCount = n;
    }

    int written = 0;
    for (int i = 0; i < fanCount && written < maxFans; i++) {
        char keyAc[5], keyMn[5], keyMx[5];
        snprintf(keyAc, sizeof(keyAc), "F%dAc", i);
        snprintf(keyMn, sizeof(keyMn), "F%dMn", i);
        snprintf(keyMx, sizeof(keyMx), "F%dMx", i);

        SMCKeyData_t acVal;
        if (!smc_read_key(conn, keyAc, &acVal)) {
            continue;
        }
        double currentRPM = smc_decode_numeric(&acVal);
        if (currentRPM < 0.0 || currentRPM > 10000.0) {
            continue;
        }

        double minRPM = 1100.0;
        double maxRPM = 5800.0;

        SMCKeyData_t mnVal, mxVal;
        if (smc_read_key(conn, keyMn, &mnVal)) {
            double v = smc_decode_numeric(&mnVal);
            if (v >= 0 && v < 8000) minRPM = v;
        }
        if (smc_read_key(conn, keyMx, &mxVal)) {
            double v = smc_decode_numeric(&mxVal);
            if (v > 500 && v < 10000) maxRPM = v;
        }

        outFans[written].index = i;
        snprintf(outFans[written].name, sizeof(outFans[written].name), i == 0 ? "Left System Fan" : (i == 1 ? "Right System Fan" : "System Fan %d"), i + 1);
        outFans[written].currentRPM = currentRPM;
        outFans[written].minRPM = minRPM;
        outFans[written].maxRPM = maxRPM;
        written++;
    }

    IOServiceClose(conn);
    return written;
}

int pm_read_smc_temperatures(PMThermalSensorReading *outReadings, int maxCount) {
    if (!outReadings || maxCount <= 0) return 0;

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess || !conn) return 0;

    typedef struct {
        const char *key;
        const char *label;
    } SMCKeyDescriptor;

    static const SMCKeyDescriptor descriptors[] = {
        { "Tp09", "CPU Efficiency Core 1" },
        { "Tp0T", "CPU Efficiency Core 2" },
        { "Tp01", "CPU Performance Core 1" },
        { "Tp05", "CPU Performance Core 2" },
        { "Tp0D", "CPU Performance Core 3" },
        { "Tp0H", "CPU Performance Core 4" },
        { "Tp0L", "CPU Performance Core 5" },
        { "Tp0P", "CPU Performance Core 6" },
        { "Tp0X", "CPU Performance Core 7" },
        { "Tp0b", "CPU Performance Core 8" },
        { "Tg05", "GPU Cluster 1" },
        { "Tg0D", "GPU Cluster 2" },
        { "Tg0L", "GPU Cluster 3" },
        { "Tg0T", "GPU Cluster 4" },
        { "TB0T", "Battery Sensor 1" },
        { "TB1T", "Battery Sensor 2" },
        { "TH0x", "NAND SSD Controller" },
        { "TW0P", "Wi-Fi / Airport Proximity" }
    };

    int written = 0;
    int numDesc = (int)(sizeof(descriptors) / sizeof(descriptors[0]));
    for (int i = 0; i < numDesc && written < maxCount; i++) {
        SMCKeyData_t val;
        if (smc_read_key(conn, descriptors[i].key, &val)) {
            double temp = smc_decode_numeric(&val);
            if (temp > 10.0 && temp < 125.0) {
                strncpy(outReadings[written].name, descriptors[i].label, sizeof(outReadings[written].name) - 1);
                outReadings[written].name[sizeof(outReadings[written].name) - 1] = '\0';
                outReadings[written].valueCelsius = temp;
                written++;
            }
        }
    }

    IOServiceClose(conn);
    return written;
}

// MARK: - Native Darwin libproc Process Reader (Zero Subprocess Overhead)

int pm_read_all_processes(PMProcessRawInfo *outProcs, int maxProcs) {
    if (!outProcs || maxProcs <= 0) return 0;

    int byteCount = proc_listallpids(NULL, 0);
    if (byteCount <= 0) return 0;

    int capacity = (byteCount / (int)sizeof(pid_t)) + 64;
    pid_t *pids = (pid_t *)calloc((size_t)capacity, sizeof(pid_t));
    if (!pids) return 0;

    int actualBytes = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
    int pidCount = actualBytes / (int)sizeof(pid_t);
    if (actualBytes > 0 && pidCount == 0) {
        pidCount = actualBytes;
    }
    if (pidCount > capacity) pidCount = capacity;

    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    uint64_t numer = timebase.numer > 0 ? timebase.numer : 1;
    uint64_t denom = timebase.denom > 0 ? timebase.denom : 1;

    int written = 0;
    for (int i = 0; i < pidCount && written < maxProcs; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        struct proc_taskallinfo taskInfo;
        memset(&taskInfo, 0, sizeof(taskInfo));
        int ret = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &taskInfo, sizeof(taskInfo));
        if (ret <= 0) {
            continue;
        }

        outProcs[written].pid = (int32_t)pid;
        outProcs[written].ppid = (int32_t)taskInfo.pbsd.pbi_ppid;
        outProcs[written].uid = taskInfo.pbsd.pbi_uid;

        const char *nameSrc = taskInfo.pbsd.pbi_name[0] != '\0' ? taskInfo.pbsd.pbi_name : taskInfo.pbsd.pbi_comm;
        strncpy(outProcs[written].name, nameSrc, sizeof(outProcs[written].name) - 1);
        outProcs[written].name[sizeof(outProcs[written].name) - 1] = '\0';

        char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
        memset(pathBuf, 0, sizeof(pathBuf));
        if (proc_pidpath(pid, pathBuf, sizeof(pathBuf)) > 0) {
            strncpy(outProcs[written].path, pathBuf, sizeof(outProcs[written].path) - 1);
            outProcs[written].path[sizeof(outProcs[written].path) - 1] = '\0';
        } else {
            strncpy(outProcs[written].path, outProcs[written].name, sizeof(outProcs[written].path) - 1);
        }

        outProcs[written].residentBytes = taskInfo.ptinfo.pti_resident_size;
        outProcs[written].totalUserTimeNs = (taskInfo.ptinfo.pti_total_user * numer) / denom;
        outProcs[written].totalSystemTimeNs = (taskInfo.ptinfo.pti_total_system * numer) / denom;
        outProcs[written].threadCount = taskInfo.ptinfo.pti_threadnum;
        outProcs[written].status = (int32_t)taskInfo.pbsd.pbi_status;
        written++;
    }

    free(pids);
    return written;
}

int pm_read_process_args_env(int32_t pid, char *outBuffer, int bufferSize) {
    if (!outBuffer || bufferSize <= 16 || pid <= 0) return 0;

    int mib[3] = { CTL_KERN, KERN_PROCARGS2, (int)pid };
    size_t size = 65536;
    char *raw = (char *)malloc(size);
    if (!raw) return 0;

    if (sysctl(mib, 3, raw, &size, NULL, 0) != 0 || size <= sizeof(int)) {
        free(raw);
        return 0;
    }

    int written = 0;
    size_t pos = sizeof(int); // skip argc int
    bool inToken = false;

    while (pos < size && written < (bufferSize - 2)) {
        char c = raw[pos++];
        if (c == '\0') {
            if (inToken) {
                outBuffer[written++] = '\n';
                inToken = false;
            }
        } else if ((unsigned char)c >= 32 && (unsigned char)c < 127) {
            outBuffer[written++] = c;
            inToken = true;
        }
    }

    outBuffer[written] = '\0';
    free(raw);
    return written;
}

int64_t pm_read_iogpu_wired_limit_mb(void) {
    int64_t val64 = 0;
    size_t sz64 = sizeof(val64);
    if (sysctlbyname("iogpu.wired_limit_mb", &val64, &sz64, NULL, 0) == 0) {
        return val64;
    }
    int32_t val32 = 0;
    size_t sz32 = sizeof(val32);
    if (sysctlbyname("iogpu.wired_limit_mb", &val32, &sz32, NULL, 0) == 0) {
        return (int64_t)val32;
    }
    return 0;
}
