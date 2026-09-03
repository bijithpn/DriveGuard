#ifndef NATIVE_STORAGE_STORAGE_BACKEND_H_
#define NATIVE_STORAGE_STORAGE_BACKEND_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace driveguard {

struct NativeDeviceInfo {
  std::string id;  // "linux-<sysfs block device name>", e.g. "linux-nvme0n1", "linux-sda".
  std::string model;
  std::string manufacturer;
  std::string serial;
  std::string type;            // "nvme" | "ssd" | "hdd" | "unknown"
  std::string interface_type;  // "nvme" | "sata" | "usb" | "scsi" | "unknown"
  std::optional<int64_t> capacity_bytes;
  bool removable = false;
};

struct NativeTemperatureInfo {
  double celsius = 0.0;
  std::string sensor_id;
  std::string sensor_name;
  bool is_primary = true;
};

struct NativeVolumeInfo {
  std::string id;  // the partition's block device path, e.g. "/dev/nvme0n1p1".
  std::optional<std::string> mount_point;
  std::optional<std::string> filesystem;
  bool is_read_only = false;
  bool is_boot_volume = false;
  std::optional<int64_t> total_bytes;
  std::optional<int64_t> used_bytes;
  std::optional<int64_t> free_bytes;
};

struct NativeCapacityInfo {
  std::optional<int64_t> total_bytes;
  std::optional<int64_t> used_bytes;
  std::optional<int64_t> free_bytes;
};

// Cumulative counters read from /sys/block/<name>/stat (kernel block layer
// I/O accounting, see Documentation/admin-guide/iostats.rst) - fields 1, 3,
// 5, 7, 10 in that doc's numbering. Callers diff two samples over elapsed
// wall-clock time to get a rate.
struct NativeActivityCounters {
  int64_t reads_completed = 0;
  int64_t sectors_read = 0;      // 512-byte units regardless of actual sector size.
  int64_t writes_completed = 0;
  int64_t sectors_written = 0;
  int64_t io_ms = 0;  // time spent doing I/Os, milliseconds - basis for %util.
};

struct NativeHealthInfo {
  std::string status;
  std::optional<int> percentage_used;
  std::optional<int> available_spare_percent;
  std::optional<std::string> critical_warning;
  std::optional<int64_t> media_errors;
  std::optional<int64_t> power_cycles;
  std::optional<int64_t> power_on_hours;
  std::optional<int64_t> unsafe_shutdowns;
  std::optional<bool> smart_passed;
};

enum class NativeStorageStatus { kOk, kUnsupported, kPermissionDenied, kDeviceNotFound, kNativeError };

template <typename T>
struct NativeResult {
  NativeStorageStatus status = NativeStorageStatus::kOk;
  std::optional<T> value;
  std::string message;
};

// Linux native storage telemetry backend.
//
// Enumeration and hwmon temperature are plain file reads under /sys/block
// (kernel-native, no external tool, no elevated permission needed) -
// functionally the same source the existing Dart LinuxStorageMonitor
// already uses, just implemented natively for architectural symmetry with
// Windows/macOS (see docs/architecture.md).
//
// The genuinely new capability here is NVME_IOCTL_ADMIN_CMD: a direct
// "Get Log Page" (SMART/Health Information, log ID 0x02) admin command
// against /dev/nvme<N> (the controller device, not the nsN namespace
// block device), giving full NVMe health (power cycles, power-on hours,
// unsafe shutdowns, media errors, available spare, percentage used) plus
// composite temperature without spawning `nvme-cli`. This requires read
// access to the /dev/nvme<N> char device (root, or membership of a group
// with a udev rule granting it - see docs/permissions.md); on failure this
// backend reports kPermissionDenied/kUnsupported and
// FallbackStorageMonitor falls through to sysfs hwmon / nvme-cli /
// smartctl exactly as before.
//
// ATA SMART (SATA/most USB-SATA bridges) uses HDIO_DRIVE_CMD with the
// legacy WIN_SMART/SMART_READ_VALUES subcommand. This ioctl is older and
// less consistently supported across USB bridges and NVMe-over-SATA
// translation layers than SG_IO/ATA_16 would be; it is deliberately kept
// simple here specifically *because* smartctl remains the fallback for
// any bridge/controller it doesn't work on.
//
// IMPORTANT: written against the documented Linux NVMe/ATA ioctl UAPIs but
// not compiled or run on Linux in this environment (no Linux machine
// available during development) - see docs/linux-telemetry.md. Smoke-test
// on real NVMe/SATA/USB hardware before trusting in production.
class StorageBackend {
 public:
  static StorageBackend& Instance();

  std::vector<NativeDeviceInfo> EnumerateDevices();
  NativeResult<NativeTemperatureInfo> ReadTemperature(const std::string& device_id);
  NativeResult<NativeHealthInfo> ReadHealth(const std::string& device_id);

  // Every distinct temperature sensor the device reports (spec section 12) -
  // for NVMe, the health log's up-to-8 "Temperature Sensor N" fields in
  // addition to the composite reading; empty (not an error) when the
  // device only has the single composite/hwmon reading already covered by
  // [ReadTemperature].
  NativeResult<std::vector<NativeTemperatureInfo>> ReadSensors(const std::string& device_id);

  // Partitions of this block device (/sys/block/<name>/<name>N or
  // <name>pN for NVMe), matched against /proc/mounts for mount
  // point/filesystem/read-only, and statvfs() on the mount point for
  // capacity - the PhysicalDisk -> Partition -> Volume split the Dart
  // model expects. A partition that exists but isn't mounted is still
  // returned, with capacity fields unset.
  std::vector<NativeVolumeInfo> EnumerateVolumes(const std::string& device_id);

  // Aggregate capacity for the whole block device: total from
  // /sys/block/<name>/size (authoritative), used/free summed across
  // EnumerateVolumes().
  NativeCapacityInfo GetCapacity(const std::string& device_id);

  // Raw /sys/block/<name>/stat snapshot - std::nullopt when the file is
  // missing/unreadable (e.g. device just disconnected), never a fabricated
  // zero.
  std::optional<NativeActivityCounters> ReadActivityCounters(const std::string& device_id);

 private:
  StorageBackend() = default;

  // "linux-<name>" -> name, validated to the same safe charset sysfs block
  // device names always use ([a-zA-Z0-9]) - never trusted beyond that
  // before being used to build a fixed /dev or /sys path.
  static std::optional<std::string> ParseSysName(const std::string& device_id);
};

}  // namespace driveguard

#endif  // NATIVE_STORAGE_STORAGE_BACKEND_H_
