#include "storage_backend.h"

#include <dirent.h>
#include <fcntl.h>
#include <linux/hdreg.h>
#include <regex.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <sstream>

// See storage_backend.h for the overall design rationale. Every ioctl/file
// read here is wrapped so a failure on one device is reported as a typed
// [NativeStorageStatus] and never crashes or blocks enumeration/telemetry
// for any other device (spec section 27 "error isolation").

namespace driveguard {

namespace {

// Minimal local declaration of the NVMe admin-command ioctl UAPI
// (linux/nvme_ioctl.h), which is not guaranteed present in every build
// environment's headers. This mirrors the kernel's stable struct
// nvme_admin_cmd byte-for-byte (unchanged since NVMe support was added in
// Linux 4.x) so it links correctly against any recent kernel without a
// compile-time dependency on <linux/nvme_ioctl.h> being installed.
struct NvmeAdminCmd {
  uint8_t opcode;
  uint8_t flags;
  uint16_t rsvd1;
  uint32_t nsid;
  uint32_t cdw2;
  uint32_t cdw3;
  uint64_t metadata;
  uint64_t addr;
  uint32_t metadata_len;
  uint32_t data_len;
  uint32_t cdw10;
  uint32_t cdw11;
  uint32_t cdw12;
  uint32_t cdw13;
  uint32_t cdw14;
  uint32_t cdw15;
  uint32_t timeout_ms;
  uint32_t result;
};
#define DG_NVME_IOCTL_ADMIN_CMD _IOWR('N', 0x41, struct NvmeAdminCmd)
constexpr uint8_t kNvmeOpGetLogPage = 0x02;
constexpr uint32_t kNvmeLogPageHealthInfo = 0x02;

constexpr int kNvmeAdminTimeoutMs = 3000;

bool IsSkippedBlockDevice(const std::string& name) {
  static const std::vector<std::string> prefixes = {"loop", "ram", "zram", "dm-", "sr", "fd"};
  for (const auto& p : prefixes) {
    if (name.rfind(p, 0) == 0) return true;
  }
  return false;
}

std::optional<std::string> ReadSysfsString(const std::string& path) {
  std::ifstream f(path);
  if (!f.is_open()) return std::nullopt;
  std::string line;
  std::getline(f, line);
  size_t start = line.find_first_not_of(" \t\r\n");
  if (start == std::string::npos) return std::nullopt;
  size_t end = line.find_last_not_of(" \t\r\n");
  return line.substr(start, end - start + 1);
}

// "nvme0n1" -> "nvme0" (the controller char device). Naively trimming the
// last "n<digits>" would also break on names without a namespace suffix,
// so this only strips a *trailing* "n<digits>" segment, matching the
// scheme actual NVMe block devices use.
std::string NvmeControllerName(const std::string& block_name) {
  size_t i = block_name.size();
  while (i > 0 && isdigit(static_cast<unsigned char>(block_name[i - 1]))) i--;
  if (i > 0 && i < block_name.size() && block_name[i - 1] == 'n' && i >= 2) {
    return block_name.substr(0, i - 1);
  }
  return block_name;
}

uint16_t ReadU16LE(const uint8_t* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }

uint64_t ReadU64LE(const uint8_t* p) {
  uint64_t v = 0;
  for (int i = 0; i < 8; i++) v |= (static_cast<uint64_t>(p[i]) << (8 * i));
  return v;
}

// Runs the NVMe "Get Log Page" admin command for the SMART/Health
// Information log against the controller device (/dev/nvme<N>, not the
// n1 namespace block device). Returns the raw 512-byte log page on
// success.
std::optional<std::vector<uint8_t>> ReadNvmeHealthLog(const std::string& sys_name,
                                                        NativeStorageStatus* out_status) {
  std::string controller = NvmeControllerName(sys_name);
  std::string path = "/dev/" + controller;
  int fd = open(path.c_str(), O_RDONLY);
  if (fd < 0) {
    *out_status = (errno == EACCES) ? NativeStorageStatus::kPermissionDenied
                                     : NativeStorageStatus::kUnsupported;
    return std::nullopt;
  }

  std::vector<uint8_t> buffer(512, 0);
  NvmeAdminCmd cmd = {};
  cmd.opcode = kNvmeOpGetLogPage;
  cmd.nsid = 0xFFFFFFFF;  // controller-wide log, not namespace-specific
  cmd.addr = reinterpret_cast<uint64_t>(buffer.data());
  cmd.data_len = static_cast<uint32_t>(buffer.size());
  // cdw10: bits 0-7 = Log Page Identifier, bits 16-31 = Number of Dwords
  // (NUMD) minus one. 512 bytes = 128 dwords, so NUMD-1 = 127.
  cmd.cdw10 = kNvmeLogPageHealthInfo | (127u << 16);
  cmd.timeout_ms = kNvmeAdminTimeoutMs;

  int rc = ioctl(fd, DG_NVME_IOCTL_ADMIN_CMD, &cmd);
  int ioctlErrno = errno;
  close(fd);

  if (rc < 0) {
    *out_status =
        (ioctlErrno == EACCES || ioctlErrno == EPERM) ? NativeStorageStatus::kPermissionDenied
                                                        : NativeStorageStatus::kUnsupported;
    return std::nullopt;
  }
  *out_status = NativeStorageStatus::kOk;
  return buffer;
}

}  // namespace

StorageBackend& StorageBackend::Instance() {
  static StorageBackend instance;
  return instance;
}

std::optional<std::string> StorageBackend::ParseSysName(const std::string& device_id) {
  const std::string prefix = "linux-";
  if (device_id.rfind(prefix, 0) != 0) return std::nullopt;
  std::string name = device_id.substr(prefix.size());
  if (name.empty() || name.size() > 32) return std::nullopt;
  for (char c : name) {
    if (!isalnum(static_cast<unsigned char>(c))) return std::nullopt;  // never trust beyond this
  }
  return name;
}

std::vector<NativeDeviceInfo> StorageBackend::EnumerateDevices() {
  std::vector<NativeDeviceInfo> devices;
  DIR* dir = opendir("/sys/block");
  if (dir == nullptr) return devices;

  struct dirent* entry;
  while ((entry = readdir(dir)) != nullptr) {
    std::string name = entry->d_name;
    if (name == "." || name == "..") continue;
    if (IsSkippedBlockDevice(name)) continue;

    NativeDeviceInfo info;
    info.id = "linux-" + name;

    bool isNvme = name.rfind("nvme", 0) == 0;
    auto model = ReadSysfsString("/sys/block/" + name + "/device/model");
    if (!model.has_value() && isNvme) {
      model = ReadSysfsString("/sys/class/nvme/" + NvmeControllerName(name) + "/model");
    }
    info.model = model.value_or("");
    info.serial = ReadSysfsString("/sys/block/" + name + "/device/serial").value_or("");

    auto sizeSectors = ReadSysfsString("/sys/block/" + name + "/size");
    if (sizeSectors.has_value()) {
      try {
        info.capacity_bytes = std::stoll(*sizeSectors) * 512;
      } catch (...) {
      }
    }

    auto removableFlag = ReadSysfsString("/sys/block/" + name + "/removable");
    info.removable = removableFlag.has_value() && *removableFlag == "1";

    auto rotational = ReadSysfsString("/sys/block/" + name + "/queue/rotational");

    if (isNvme) {
      info.type = "nvme";
      info.interface_type = "nvme";
    } else if (name.rfind("sd", 0) == 0 || name.rfind("hd", 0) == 0) {
      info.interface_type = info.removable ? "usb" : "sata";
      info.type = (rotational.has_value() && *rotational == "1") ? "hdd" : "ssd";
    } else {
      info.type = "unknown";
      info.interface_type = "unknown";
    }

    devices.push_back(std::move(info));
  }
  closedir(dir);
  return devices;
}

NativeResult<NativeTemperatureInfo> StorageBackend::ReadTemperature(const std::string& device_id) {
  NativeResult<NativeTemperatureInfo> result;
  auto sysName = ParseSysName(device_id);
  if (!sysName.has_value()) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  // 1. sysfs hwmon - same source the Dart backend already reads, kept
  //    first because it needs no elevated access at all.
  std::string hwmonRoot = "/sys/block/" + *sysName + "/device";
  DIR* dir = opendir(hwmonRoot.c_str());
  if (dir != nullptr) {
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
      std::string name = entry->d_name;
      if (name.rfind("hwmon", 0) != 0) continue;
      std::string hwmonDirPath = hwmonRoot + "/" + name;
      DIR* hwmonDir = opendir(hwmonDirPath.c_str());
      if (hwmonDir == nullptr) continue;
      struct dirent* f;
      while ((f = readdir(hwmonDir)) != nullptr) {
        std::string fname = f->d_name;
        if (fname.rfind("temp", 0) == 0 && fname.size() > 10 &&
            fname.substr(fname.size() - 10) == "_input") {
          auto raw = ReadSysfsString(hwmonDirPath + "/" + fname);
          if (raw.has_value()) {
            try {
              double milli = std::stod(*raw);
              closedir(hwmonDir);
              closedir(dir);
              NativeTemperatureInfo temp;
              temp.celsius = milli / 1000.0;
              temp.sensor_id = "composite";
              result.value = temp;
              return result;
            } catch (...) {
            }
          }
        }
      }
      closedir(hwmonDir);
    }
    closedir(dir);
  }

  // 2. NVMe admin Get Log Page - richer than hwmon and doesn't need
  //    nvme-cli, but does need /dev/nvme<N> access.
  if (sysName->rfind("nvme", 0) == 0) {
    NativeStorageStatus logStatus;
    auto log = ReadNvmeHealthLog(*sysName, &logStatus);
    if (log.has_value()) {
      uint16_t kelvin = ReadU16LE(log->data() + 1);
      if (kelvin != 0) {
        NativeTemperatureInfo temp;
        temp.celsius = static_cast<double>(kelvin) - 273.15;
        temp.sensor_id = "composite";
        result.value = temp;
        return result;
      }
    } else if (logStatus == NativeStorageStatus::kPermissionDenied) {
      result.status = logStatus;
      result.message = "Reading /dev/" + NvmeControllerName(*sysName) +
                        " requires root or an appropriate udev permission rule.";
      return result;
    }
  }

  // No native source available - FallbackStorageMonitor tries nvme-cli /
  // smartctl next.
  result.status = NativeStorageStatus::kUnsupported;
  return result;
}

NativeResult<NativeHealthInfo> StorageBackend::ReadHealth(const std::string& device_id) {
  NativeResult<NativeHealthInfo> result;
  auto sysName = ParseSysName(device_id);
  if (!sysName.has_value()) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  if (sysName->rfind("nvme", 0) == 0) {
    NativeStorageStatus logStatus;
    auto log = ReadNvmeHealthLog(*sysName, &logStatus);
    if (!log.has_value()) {
      result.status = logStatus;
      return result;
    }
    const uint8_t* l = log->data();
    uint8_t criticalWarning = l[0];
    uint8_t availableSpare = l[3];
    uint8_t availableSpareThreshold = l[4];
    uint8_t percentageUsed = l[5];
    uint64_t dataUnitsRead = ReadU64LE(l + 32);
    uint64_t dataUnitsWritten = ReadU64LE(l + 48);
    uint64_t powerCycles = ReadU64LE(l + 112);
    uint64_t powerOnHours = ReadU64LE(l + 128);
    uint64_t unsafeShutdowns = ReadU64LE(l + 144);
    uint64_t mediaErrors = ReadU64LE(l + 160);

    NativeHealthInfo health;
    health.status = criticalWarning != 0 ? "warning" : "healthy";
    health.percentage_used = percentageUsed;
    health.available_spare_percent = availableSpare;
    health.available_spare_threshold = availableSpareThreshold;
    health.data_units_read = static_cast<int64_t>(dataUnitsRead);
    health.data_units_written = static_cast<int64_t>(dataUnitsWritten);
    if (criticalWarning != 0) {
      std::ostringstream oss;
      oss << "0x" << std::hex << static_cast<int>(criticalWarning);
      health.critical_warning = oss.str();
    }
    health.power_cycles = static_cast<int64_t>(powerCycles);
    health.power_on_hours = static_cast<int64_t>(powerOnHours);
    health.unsafe_shutdowns = static_cast<int64_t>(unsafeShutdowns);
    health.media_errors = static_cast<int64_t>(mediaErrors);
    result.value = health;
    return result;
  }

  // ATA/SATA: HDIO_DRIVE_CMD / SMART_READ_VALUES. Kept deliberately simple
  // (reallocated/pending sector heuristic, matching the legacy smartctl
  // backend's approach) - smartctl remains the fallback for any
  // bridge/controller this ioctl doesn't work through.
  std::string path = "/dev/" + *sysName;
  int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK);
  if (fd < 0) {
    result.status =
        (errno == EACCES) ? NativeStorageStatus::kPermissionDenied : NativeStorageStatus::kUnsupported;
    return result;
  }

  uint8_t args[4 + 512] = {0};
  args[0] = WIN_SMART;
  args[1] = SMART_READ_VALUES;
  args[2] = 1;
  int rc = ioctl(fd, HDIO_DRIVE_CMD, args);
  int ioctlErrno = errno;
  close(fd);
  if (rc != 0) {
    result.status =
        (ioctlErrno == EACCES) ? NativeStorageStatus::kPermissionDenied : NativeStorageStatus::kUnsupported;
    return result;
  }

  const uint8_t* smartData = args + 4;
  bool hasReallocated = false, hasPending = false;
  for (int i = 2; i + 12 <= 362; i += 12) {
    uint8_t attributeId = smartData[i];
    if (attributeId == 5 && smartData[i + 5] != 0) hasReallocated = true;
    if (attributeId == 197 && smartData[i + 5] != 0) hasPending = true;
  }

  NativeHealthInfo health;
  health.status = (hasReallocated || hasPending) ? "warning" : "healthy";
  health.smart_passed = !hasReallocated && !hasPending;
  result.value = health;
  return result;
}

NativeResult<std::vector<NativeTemperatureInfo>> StorageBackend::ReadSensors(
    const std::string& device_id) {
  NativeResult<std::vector<NativeTemperatureInfo>> result;
  auto sysName = ParseSysName(device_id);
  if (!sysName.has_value()) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  if (sysName->rfind("nvme", 0) != 0) {
    result.status = NativeStorageStatus::kUnsupported;
    return result;
  }

  NativeStorageStatus logStatus;
  auto log = ReadNvmeHealthLog(*sysName, &logStatus);
  if (!log.has_value()) {
    result.status = logStatus;
    return result;
  }

  std::vector<NativeTemperatureInfo> sensors;
  uint16_t composite = ReadU16LE(log->data() + 1);
  if (composite != 0) {
    NativeTemperatureInfo t;
    t.celsius = static_cast<double>(composite) - 273.15;
    t.sensor_id = "composite";
    t.sensor_name = "Composite";
    t.is_primary = true;
    sensors.push_back(t);
  }
  // TemperatureSensor1..8 (u16 Kelvin each) at byte offsets 200..214 in the
  // SMART/Health Information log page (NVMe base spec section 5.14.1.3).
  // 0 means the controller does not implement that sensor.
  for (int i = 0; i < 8; i++) {
    size_t offset = 200 + i * 2;
    uint16_t kelvin = ReadU16LE(log->data() + offset);
    if (kelvin == 0) continue;
    NativeTemperatureInfo t;
    t.celsius = static_cast<double>(kelvin) - 273.15;
    t.sensor_id = "sensor" + std::to_string(i + 1);
    t.sensor_name = "Sensor " + std::to_string(i + 1);
    t.is_primary = false;
    sensors.push_back(t);
  }

  if (sensors.size() > 1) {
    result.value = sensors;
  } else {
    result.status = NativeStorageStatus::kUnsupported;
  }
  return result;
}

namespace {

struct MountEntry {
  std::string device;
  std::string mountPoint;
  std::string filesystem;
  bool readOnly = false;
};

// Parses /proc/mounts (kernel-native, always present, no permission
// needed) into device -> mount point/filesystem/options. Octal escapes
// (\040 for space, etc.) used by the kernel for paths containing spaces
// are unescaped since mount points legitimately can contain them.
std::string UnescapeOctal(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '\\' && i + 3 < s.size() && isdigit(static_cast<unsigned char>(s[i + 1]))) {
      int value = (s[i + 1] - '0') * 64 + (s[i + 2] - '0') * 8 + (s[i + 3] - '0');
      out.push_back(static_cast<char>(value));
      i += 3;
    } else {
      out.push_back(s[i]);
    }
  }
  return out;
}

std::vector<MountEntry> ReadProcMounts() {
  std::vector<MountEntry> mounts;
  std::ifstream f("/proc/mounts");
  if (!f.is_open()) return mounts;
  std::string line;
  while (std::getline(f, line)) {
    std::istringstream iss(line);
    std::string device, mountPoint, fstype, options;
    if (!(iss >> device >> mountPoint >> fstype >> options)) continue;
    MountEntry entry;
    entry.device = UnescapeOctal(device);
    entry.mountPoint = UnescapeOctal(mountPoint);
    entry.filesystem = fstype;
    entry.readOnly = options.substr(0, 2) == "ro";
    mounts.push_back(std::move(entry));
  }
  return mounts;
}

// Partition child names of a whole-disk sysfs name: entries directly under
// /sys/block/<name>/ that are themselves registered block devices (have a
// "partition" file) - the kernel's own definition of "this is a
// partition", not a guessed naming pattern.
std::vector<std::string> PartitionNames(const std::string& wholeName) {
  std::vector<std::string> names;
  std::string root = "/sys/block/" + wholeName;
  DIR* dir = opendir(root.c_str());
  if (dir == nullptr) return names;
  struct dirent* entry;
  while ((entry = readdir(dir)) != nullptr) {
    std::string name = entry->d_name;
    if (name == "." || name == "..") continue;
    struct stat st;
    std::string partitionMarker = root + "/" + name + "/partition";
    if (stat(partitionMarker.c_str(), &st) == 0) {
      names.push_back(name);
    }
  }
  closedir(dir);
  return names;
}

}  // namespace

std::vector<NativeVolumeInfo> StorageBackend::EnumerateVolumes(const std::string& device_id) {
  std::vector<NativeVolumeInfo> result;
  auto sysName = ParseSysName(device_id);
  if (!sysName.has_value()) return result;

  auto mounts = ReadProcMounts();
  for (const auto& partitionName : PartitionNames(*sysName)) {
    NativeVolumeInfo info;
    info.id = "/dev/" + partitionName;

    const MountEntry* matched = nullptr;
    for (const auto& m : mounts) {
      if (m.device == info.id) {
        matched = &m;
        break;
      }
    }

    if (matched != nullptr) {
      info.mount_point = matched->mountPoint;
      info.filesystem = matched->filesystem;
      info.is_read_only = matched->readOnly;
      info.is_boot_volume = (matched->mountPoint == "/");

      struct statvfs vfs;
      if (statvfs(matched->mountPoint.c_str(), &vfs) == 0) {
        uint64_t total = static_cast<uint64_t>(vfs.f_blocks) * vfs.f_frsize;
        uint64_t free = static_cast<uint64_t>(vfs.f_bfree) * vfs.f_frsize;
        info.total_bytes = static_cast<int64_t>(total);
        info.free_bytes = static_cast<int64_t>(free);
        info.used_bytes = static_cast<int64_t>(total - free);
      }
    }

    result.push_back(std::move(info));
  }
  return result;
}

NativeCapacityInfo StorageBackend::GetCapacity(const std::string& device_id) {
  NativeCapacityInfo capacity;
  auto sysName = ParseSysName(device_id);
  if (!sysName.has_value()) return capacity;

  auto sizeSectors = ReadSysfsString("/sys/block/" + *sysName + "/size");
  if (sizeSectors.has_value()) {
    try {
      capacity.total_bytes = std::stoll(*sizeSectors) * 512;
    } catch (...) {
    }
  }

  int64_t usedSum = 0, freeSum = 0;
  bool haveAny = false;
  for (const auto& v : EnumerateVolumes(device_id)) {
    if (v.used_bytes.has_value()) {
      usedSum += *v.used_bytes;
      haveAny = true;
    }
    if (v.free_bytes.has_value()) {
      freeSum += *v.free_bytes;
      haveAny = true;
    }
  }
  if (haveAny) {
    capacity.used_bytes = usedSum;
    capacity.free_bytes = freeSum;
  }
  return capacity;
}

std::optional<NativeActivityCounters> StorageBackend::ReadActivityCounters(const std::string& device_id) {
  auto sysName = ParseSysName(device_id);
  if (!sysName.has_value()) return std::nullopt;

  auto line = ReadSysfsString("/sys/block/" + *sysName + "/stat");
  if (!line.has_value()) return std::nullopt;

  // Whitespace-separated fields per Documentation/admin-guide/iostats.rst;
  // only 1, 3, 5, 7, 10 are needed here (1-indexed in that doc).
  std::istringstream iss(*line);
  std::vector<int64_t> fields;
  int64_t v;
  while (iss >> v) fields.push_back(v);
  if (fields.size() < 10) return std::nullopt;

  NativeActivityCounters counters;
  counters.reads_completed = fields[0];
  counters.sectors_read = fields[2];
  counters.writes_completed = fields[4];
  counters.sectors_written = fields[6];
  counters.io_ms = fields[9];
  return counters;
}

}  // namespace driveguard
