#ifndef NATIVE_STORAGE_STORAGE_BACKEND_H_
#define NATIVE_STORAGE_STORAGE_BACKEND_H_

#include <windows.h>

#include <optional>
#include <string>
#include <vector>

namespace driveguard {

// One physical disk as enumerated through \\.\PhysicalDriveN +
// IOCTL_STORAGE_QUERY_PROPERTY (StorageDeviceProperty). Mirrors the Dart
// native data contract (docs/architecture.md).
struct NativeDeviceInfo {
  std::string id;  // "windows-<PhysicalDrive index>" - see storage_backend.cpp header comment.
  std::string model;
  std::string manufacturer;
  std::string serial;
  std::string type;       // "nvme" | "ssd" | "hdd" | "unknown"
  std::string interface_type;  // "nvme" | "sata" | "usb" | "scsi" | "unknown"
  std::optional<int64_t> capacity_bytes;
  bool removable = false;
};

struct NativeTemperatureInfo {
  double celsius = 0.0;
  std::string sensor_id;  // "composite" (NVMe) or "smart-194"/"smart-190" (ATA)
  std::string sensor_name;
  bool is_primary = true;
};

struct NativeHealthInfo {
  std::string status;  // "healthy" | "warning" | "critical" | "unknown"
  std::optional<int> percentage_used;
  std::optional<int> available_spare_percent;
  std::optional<std::string> critical_warning;
  std::optional<int64_t> media_errors;
  std::optional<int64_t> power_cycles;
  std::optional<int64_t> power_on_hours;
  std::optional<int64_t> unsafe_shutdowns;
  std::optional<bool> smart_passed;
};

enum class NativeStorageStatus {
  kOk,
  kUnsupported,       // structurally no sensor/log for this device (not an error)
  kPermissionDenied,  // handle/DeviceIoControl failed with access-denied
  kDeviceNotFound,
  kNativeError,
};

template <typename T>
struct NativeResult {
  NativeStorageStatus status = NativeStorageStatus::kOk;
  std::optional<T> value;
  std::string message;
};

// Windows native storage telemetry backend.
//
// Enumeration and temperature both go through public, documented
// DeviceIoControl IOCTLs against \\.\PhysicalDriveN handles - no PowerShell,
// no WMI. See storage_backend.cpp for exactly which IOCTLs and why.
//
// IMPORTANT (matches the pre-existing honesty convention in
// lib/infrastructure/storage/windows_storage_monitor.dart): this has been
// written against Microsoft's public IOCTL documentation but has not been
// compiled or run on physical Windows hardware in this environment (no
// Windows machine available). It should be smoke-tested on real NVMe/SATA/
// USB hardware before being trusted in production - see
// docs/windows-telemetry.md.
class StorageBackend {
 public:
  static StorageBackend& Instance();

  std::vector<NativeDeviceInfo> EnumerateDevices();
  NativeResult<NativeTemperatureInfo> ReadTemperature(const std::string& device_id);
  NativeResult<NativeHealthInfo> ReadHealth(const std::string& device_id);

  // Every distinct temperature sensor the device reports (spec section 12):
  // for NVMe, the composite sensor plus any of the health log's up-to-8
  // named "Temperature Sensor N" fields that are actually populated; for
  // ATA/SATA, attribute 194 (Temperature) and, when also present and
  // distinct, attribute 190 (Airflow Temperature). Returns an empty vector
  // (not an error) when the device exposes only the single composite/194
  // reading already covered by [ReadTemperature].
  NativeResult<std::vector<NativeTemperatureInfo>> ReadSensors(const std::string& device_id);

 private:
  StorageBackend() = default;

  // Parses "windows-<n>" -> n, or -1 if malformed. Never trusts the string
  // beyond that - it is used only to build a fixed \\.\PhysicalDriveN
  // path, never passed to a shell.
  static int ParseDriveIndex(const std::string& device_id);
};

}  // namespace driveguard

#endif  // NATIVE_STORAGE_STORAGE_BACKEND_H_
