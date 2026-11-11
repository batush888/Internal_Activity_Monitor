#ifndef IOKitHIDBridge_h
#define IOKitHIDBridge_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char name[64];
    double valueCelsius;
} PMThermalSensorReading;

typedef struct {
    int index;
    char name[32];
    double currentRPM;
    double minRPM;
    double maxRPM;
} PMFanReading;

typedef struct {
    int32_t pid;
    int32_t ppid;
    uint32_t uid;
    char name[64];
    char path[256];
    uint64_t residentBytes;
    uint64_t totalUserTimeNs;
    uint64_t totalSystemTimeNs;
    int32_t threadCount;
    int32_t status;
} PMProcessRawInfo;

/// Reads Apple Silicon / macOS IOHID temperature sensors into the provided buffer.
/// Returns the number of valid thermal sensors populated (up to maxCount).
int pm_read_hid_thermal_sensors(PMThermalSensorReading *outReadings, int maxCount);

/// Reads AppleSMC fan telemetry (RPM, min, max) into the provided buffer.
/// Returns the number of fans populated (up to maxFans).
int pm_read_smc_fans(PMFanReading *outFans, int maxFans);

/// Reads common AppleSMC temperature keys as a fallback or supplement to IOHID.
/// Returns the number of valid temperature readings added.
int pm_read_smc_temperatures(PMThermalSensorReading *outReadings, int maxCount);

/// Reads active processes directly from the Darwin kernel via libproc (zero subprocess overhead).
int pm_read_all_processes(PMProcessRawInfo *outProcs, int maxProcs);

/// Reads the command-line arguments and environment variables of a process via KERN_PROCARGS2,
/// joining null-separated tokens with newlines into outBuffer. Returns number of bytes written.
int pm_read_process_args_env(int32_t pid, char *outBuffer, int bufferSize);

/// Reads sysctl `iogpu.wired_limit_mb` (returns 0 if default/unset, or custom MB limit).
int64_t pm_read_iogpu_wired_limit_mb(void);

#ifdef __cplusplus
}
#endif

#endif /* IOKitHIDBridge_h */
