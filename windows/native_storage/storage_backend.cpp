#include "storage_backend.h"

#include <winioctl.h>
#include <ntddscsi.h>

#include <algorithm>
#include <cstring>
#include <sstream>
#include <string>

// Native Windows storage telemetry.
//
// Every read here goes through DeviceIoControl against a
// "\\.\PhysicalDriveN" handle - no PowerShell, no WMI, no shelling out.
// Three IOCTLs are used, all documented public Win32 storage APIs:
//
//  - IOCTL_STORAGE_QUERY_PROPERTY / StorageDeviceProperty: vendor/product/
//    serial/bus-type enumeration (STORAGE_DEVICE_DESCRIPTOR). Works
//    unprivileged (handle opened with 0 desired access) on every bus type.
//
//  - IOCTL_STORAGE_QUERY_PROPERTY / StorageDeviceProtocolSpecificProperty
//    with STORAGE_PROTOCOL_SPECIFIC_DATA{ProtocolType=ProtocolTypeNvme,
//    DataType=NVMeDataTypeLogPage, ProtocolDataRequestValue=0x02}: the
//    NVMe "SMART / Health Information" log page (NVMe base spec section
//    5.14.1.3). Byte 0 is CriticalWarning, bytes 1-2 are the composite
//    temperature in Kelvin (little-endian), bytes 32-191 hold the 128-bit
//    little-endian lifetime counters (data units, power cycles, power-on
//    hours, unsafe shutdowns, media errors, ...). This is the same log
//    page `nvme smart-log` / `smartctl -a` report - just read directly
//    instead of shelling out to a CLI tool.
//
//  - IOCTL_ATA_PASS_THROUGH with a SMART READ DATA (B0h/D0h) command: the
//    classic ATA SMART attribute table, for SATA/USB-bridged disks. The
//    194/190 attribute's first raw byte is the vendor-standard Celsius
//    encoding used by essentially every consumer SATA SSD/HDD.
//
// A single failed IOCTL on one drive must never take down enumeration or
// telemetry for any other drive - every call here is wrapped so a bad
// return code becomes NativeStorageStatus, never a crash.

namespace driveguard {

namespace {

constexpr int kMaxPhysicalDrives = 32;

HANDLE OpenDrive(int index, DWORD desired_access) {
  wchar_t path[64];
  swprintf_s(path, L"\\\\.\\PhysicalDrive%d", index);
  return CreateFileW(path, desired_access, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                      OPEN_EXISTING, 0, nullptr);
}

uint16_t ReadU16LE(const BYTE* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }

// Reads a little-endian counter up to 8 bytes wide out of a wider
// (typically 128-bit) NVMe log field - NVMe lifetime counters are 128-bit
// but never realistically exceed 64 bits in practice, so only the low 8
// bytes are decoded.
uint64_t ReadU64LE(const BYTE* p) {
  uint64_t v = 0;
  for (int i = 0; i < 8; i++) v |= (static_cast<uint64_t>(p[i]) << (8 * i));
  return v;
}

std::string BusTypeToInterface(STORAGE_BUS_TYPE bus) {
  switch (bus) {
    case BusTypeNvme:
      return "nvme";
    case BusTypeSata:
    case BusTypeAta:
      return "sata";
    case BusTypeUsb:
      return "usb";
    case BusTypeScsi:
    case BusTypeSas:
    case BusTypeRAID:
      return "scsi";
    default:
      return "unknown";
  }
}

std::string TrimmedStringAt(const BYTE* base, DWORD size, DWORD offset) {
  if (offset == 0 || offset >= size) return "";
  const char* s = reinterpret_cast<const char*>(base) + offset;
  size_t maxLen = size - offset;
  size_t len = strnlen(s, maxLen);
  std::string result(s, len);
  // Trim trailing/leading whitespace - vendor/product/serial fields are
  // fixed-width, space-padded ASCII per the SPC spec.
  size_t start = result.find_first_not_of(" \t\r\n");
  size_t end = result.find_last_not_of(" \t\r\n");
  if (start == std::string::npos) return "";
  return result.substr(start, end - start + 1);
}

bool QueryDeviceDescriptor(HANDLE h, std::vector<BYTE>* out) {
  STORAGE_PROPERTY_QUERY query = {};
  query.PropertyId = StorageDeviceProperty;
  query.QueryType = PropertyStandardQuery;

  out->resize(1024);
  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), out->data(),
                             static_cast<DWORD>(out->size()), &bytesReturned, nullptr);
  return ok != FALSE;
}

constexpr DWORD kNvmeLogPageSize = 512;

// Issues the NVMe "SMART / Health Information" log page query (see the
// file header comment) and returns the raw log page bytes on success -
// shared by ReadTemperature, ReadHealth and ReadSensors so the three don't
// each hand-roll the STORAGE_PROTOCOL_SPECIFIC_DATA request separately.
bool FetchNvmeHealthLog(HANDLE h, std::vector<BYTE>* log_out) {
  std::vector<BYTE> buffer(sizeof(STORAGE_PROPERTY_QUERY) + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) +
                            kNvmeLogPageSize);

  auto* query = reinterpret_cast<STORAGE_PROPERTY_QUERY*>(buffer.data());
  query->PropertyId = StorageDeviceProtocolSpecificProperty;
  query->QueryType = PropertyStandardQuery;

  auto* protocolData = reinterpret_cast<STORAGE_PROTOCOL_SPECIFIC_DATA*>(query->AdditionalParameters);
  protocolData->ProtocolType = ProtocolTypeNvme;
  protocolData->DataType = NVMeDataTypeLogPage;
  protocolData->ProtocolDataRequestValue = 0x02;  // NVME_LOG_PAGE_HEALTH_INFO
  protocolData->ProtocolDataRequestSubValue = 0;
  protocolData->ProtocolDataOffset = sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR);
  protocolData->ProtocolDataLength = kNvmeLogPageSize;

  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, buffer.data(),
                             static_cast<DWORD>(sizeof(STORAGE_PROPERTY_QUERY) +
                                                 sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)),
                             buffer.data(), static_cast<DWORD>(buffer.size()), &bytesReturned,
                             nullptr);
  if (!ok) return false;

  auto* returned = reinterpret_cast<STORAGE_PROTOCOL_DATA_DESCRIPTOR*>(buffer.data());
  const BYTE* logPage = buffer.data() + returned->ProtocolSpecificData.ProtocolDataOffset;
  log_out->assign(logPage, logPage + kNvmeLogPageSize);
  return true;
}

}  // namespace

StorageBackend& StorageBackend::Instance() {
  static StorageBackend instance;
  return instance;
}

int StorageBackend::ParseDriveIndex(const std::string& device_id) {
  const std::string prefix = "windows-";
  if (device_id.rfind(prefix, 0) != 0) return -1;
  std::string rest = device_id.substr(prefix.size());
  if (rest.empty()) return -1;
  for (char c : rest) {
    if (c < '0' || c > '9') return -1;  // never trust the id beyond digits
  }
  try {
    int index = std::stoi(rest);
    if (index < 0 || index >= kMaxPhysicalDrives) return -1;
    return index;
  } catch (...) {
    return -1;
  }
}

std::vector<NativeDeviceInfo> StorageBackend::EnumerateDevices() {
  std::vector<NativeDeviceInfo> devices;

  for (int i = 0; i < kMaxPhysicalDrives; i++) {
    HANDLE h = OpenDrive(i, 0);
    if (h == INVALID_HANDLE_VALUE) continue;

    std::vector<BYTE> descBuf;
    if (QueryDeviceDescriptor(h, &descBuf)) {
      auto* desc = reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(descBuf.data());
      NativeDeviceInfo info;
      info.id = "windows-" + std::to_string(i);
      std::string vendor = TrimmedStringAt(descBuf.data(), desc->Size, desc->VendorIdOffset);
      std::string product = TrimmedStringAt(descBuf.data(), desc->Size, desc->ProductIdOffset);
      info.manufacturer = vendor;
      info.model = !product.empty() ? product : vendor;
      info.serial = TrimmedStringAt(descBuf.data(), desc->Size, desc->SerialNumberOffset);
      info.interface_type = BusTypeToInterface(desc->BusType);
      info.type = info.interface_type == "nvme" ? "nvme" : "unknown";
      info.removable = desc->RemovableMedia != FALSE;

      GET_LENGTH_INFORMATION lengthInfo = {};
      DWORD bytesReturned = 0;
      if (DeviceIoControl(h, IOCTL_DISK_GET_LENGTH_INFO, nullptr, 0, &lengthInfo,
                           sizeof(lengthInfo), &bytesReturned, nullptr)) {
        info.capacity_bytes = lengthInfo.Length.QuadPart;
      }

      devices.push_back(std::move(info));
    }
    CloseHandle(h);
  }

  return devices;
}

NativeResult<NativeTemperatureInfo> StorageBackend::ReadTemperature(const std::string& device_id) {
  NativeResult<NativeTemperatureInfo> result;
  int index = ParseDriveIndex(device_id);
  if (index < 0) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  HANDLE h = OpenDrive(index, GENERIC_READ | GENERIC_WRITE);
  if (h == INVALID_HANDLE_VALUE) {
    result.status = (GetLastError() == ERROR_ACCESS_DENIED) ? NativeStorageStatus::kPermissionDenied
                                                              : NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  std::vector<BYTE> descBuf;
  STORAGE_BUS_TYPE bus = BusTypeUnknown;
  if (QueryDeviceDescriptor(h, &descBuf)) {
    bus = reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(descBuf.data())->BusType;
  }

  if (bus == BusTypeNvme) {
    // STORAGE_PROTOCOL_DATA_DESCRIPTOR header followed by the raw NVMe
    // "SMART / Health Information" log page (512 bytes per spec).
    constexpr DWORD kLogPageSize = 512;
    std::vector<BYTE> buffer(sizeof(STORAGE_PROPERTY_QUERY) + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) +
                              kLogPageSize);

    auto* query = reinterpret_cast<STORAGE_PROPERTY_QUERY*>(buffer.data());
    query->PropertyId = StorageDeviceProtocolSpecificProperty;
    query->QueryType = PropertyStandardQuery;

    auto* protocolData = reinterpret_cast<STORAGE_PROTOCOL_SPECIFIC_DATA*>(query->AdditionalParameters);
    protocolData->ProtocolType = ProtocolTypeNvme;
    protocolData->DataType = NVMeDataTypeLogPage;
    protocolData->ProtocolDataRequestValue = 0x02;  // NVME_LOG_PAGE_HEALTH_INFO
    protocolData->ProtocolDataRequestSubValue = 0;
    protocolData->ProtocolDataOffset = sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR);
    protocolData->ProtocolDataLength = kLogPageSize;

    DWORD bytesReturned = 0;
    BOOL ok = DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, buffer.data(),
                               static_cast<DWORD>(sizeof(STORAGE_PROPERTY_QUERY) +
                                                   sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)),
                               buffer.data(), static_cast<DWORD>(buffer.size()), &bytesReturned,
                               nullptr);
    CloseHandle(h);

    if (!ok) {
      // Some third-party NVMe controllers (RAID HBAs, certain USB-NVMe
      // bridges) reject this IOCTL entirely - structurally unsupported,
      // not a real error the user needs to see.
      result.status = NativeStorageStatus::kUnsupported;
      return result;
    }

    auto* returned = reinterpret_cast<STORAGE_PROTOCOL_DATA_DESCRIPTOR*>(buffer.data());
    const BYTE* logPage = buffer.data() + returned->ProtocolSpecificData.ProtocolDataOffset;

    uint16_t kelvin = ReadU16LE(logPage + 1);
    if (kelvin == 0) {
      result.status = NativeStorageStatus::kUnsupported;  // composite sensor not reported
      return result;
    }

    NativeTemperatureInfo temp;
    temp.celsius = static_cast<double>(kelvin) - 273.15;
    temp.sensor_id = "composite";
    result.value = temp;
    return result;
  }

  // ATA/SATA (and most USB-SATA bridges that pass ATA commands through):
  // SMART READ DATA via IOCTL_ATA_PASS_THROUGH.
  constexpr DWORD kSmartDataSize = 512;
  std::vector<BYTE> buffer(sizeof(ATA_PASS_THROUGH_EX) + kSmartDataSize);
  auto* ata = reinterpret_cast<ATA_PASS_THROUGH_EX*>(buffer.data());
  ata->Length = sizeof(ATA_PASS_THROUGH_EX);
  ata->AtaFlags = ATA_FLAGS_DRDY_REQUIRED | ATA_FLAGS_DATA_IN;
  ata->DataTransferLength = kSmartDataSize;
  ata->TimeOutValue = 5;
  ata->DataBufferOffset = sizeof(ATA_PASS_THROUGH_EX);
  ata->CurrentTaskFile[0] = 0xD0;  // Features: SMART READ DATA
  ata->CurrentTaskFile[1] = 0x01;  // SectorCount
  ata->CurrentTaskFile[2] = 0x01;  // SectorNumber / LBA low
  ata->CurrentTaskFile[3] = 0x4F;  // CylinderLow / LBA mid (SMART signature)
  ata->CurrentTaskFile[4] = 0xC2;  // CylinderHigh / LBA high (SMART signature)
  ata->CurrentTaskFile[5] = 0xA0;  // Device/Head
  ata->CurrentTaskFile[6] = 0xB0;  // Command: SMART

  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_ATA_PASS_THROUGH, buffer.data(),
                             static_cast<DWORD>(buffer.size()), buffer.data(),
                             static_cast<DWORD>(buffer.size()), &bytesReturned, nullptr);
  CloseHandle(h);

  if (!ok) {
    // USB bridges that don't pass ATA_PASS_THROUGH through are extremely
    // common (spec section: "Depends on bridge") - unsupported, not error.
    result.status = NativeStorageStatus::kUnsupported;
    return result;
  }

  const BYTE* smartData = buffer.data() + sizeof(ATA_PASS_THROUGH_EX);
  // Attribute table starts at byte 2, 12 bytes per attribute, ID 0 marks
  // an unused slot / end of table.
  for (int i = 2; i + 12 <= 362; i += 12) {
    BYTE attributeId = smartData[i];
    if (attributeId == 0) continue;
    if (attributeId == 194 || attributeId == 190) {  // Temperature / Airflow Temperature
      BYTE rawCelsius = smartData[i + 5];  // first byte of the 6-byte raw value
      if (rawCelsius == 0) continue;
      NativeTemperatureInfo temp;
      temp.celsius = static_cast<double>(rawCelsius);
      temp.sensor_id = std::string("smart-") + std::to_string(attributeId);
      result.value = temp;
      return result;
    }
  }

  result.status = NativeStorageStatus::kUnsupported;  // no temperature attribute present
  return result;
}

NativeResult<NativeHealthInfo> StorageBackend::ReadHealth(const std::string& device_id) {
  NativeResult<NativeHealthInfo> result;
  int index = ParseDriveIndex(device_id);
  if (index < 0) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  HANDLE h = OpenDrive(index, GENERIC_READ | GENERIC_WRITE);
  if (h == INVALID_HANDLE_VALUE) {
    result.status = (GetLastError() == ERROR_ACCESS_DENIED) ? NativeStorageStatus::kPermissionDenied
                                                              : NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  std::vector<BYTE> descBuf;
  STORAGE_BUS_TYPE bus = BusTypeUnknown;
  if (QueryDeviceDescriptor(h, &descBuf)) {
    bus = reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(descBuf.data())->BusType;
  }

  if (bus == BusTypeNvme) {
    constexpr DWORD kLogPageSize = 512;
    std::vector<BYTE> buffer(sizeof(STORAGE_PROPERTY_QUERY) + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) +
                              kLogPageSize);
    auto* query = reinterpret_cast<STORAGE_PROPERTY_QUERY*>(buffer.data());
    query->PropertyId = StorageDeviceProtocolSpecificProperty;
    query->QueryType = PropertyStandardQuery;
    auto* protocolData = reinterpret_cast<STORAGE_PROTOCOL_SPECIFIC_DATA*>(query->AdditionalParameters);
    protocolData->ProtocolType = ProtocolTypeNvme;
    protocolData->DataType = NVMeDataTypeLogPage;
    protocolData->ProtocolDataRequestValue = 0x02;
    protocolData->ProtocolDataOffset = sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR);
    protocolData->ProtocolDataLength = kLogPageSize;

    DWORD bytesReturned = 0;
    BOOL ok = DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, buffer.data(),
                               static_cast<DWORD>(sizeof(STORAGE_PROPERTY_QUERY) +
                                                   sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)),
                               buffer.data(), static_cast<DWORD>(buffer.size()), &bytesReturned,
                               nullptr);
    CloseHandle(h);
    if (!ok) {
      result.status = NativeStorageStatus::kUnsupported;
      return result;
    }

    auto* returned = reinterpret_cast<STORAGE_PROTOCOL_DATA_DESCRIPTOR*>(buffer.data());
    const BYTE* log = buffer.data() + returned->ProtocolSpecificData.ProtocolDataOffset;

    BYTE criticalWarning = log[0];
    BYTE availableSpare = log[3];
    BYTE percentageUsed = log[5];
    uint64_t powerCycles = ReadU64LE(log + 112);
    uint64_t powerOnHours = ReadU64LE(log + 128);
    uint64_t unsafeShutdowns = ReadU64LE(log + 144);
    uint64_t mediaErrors = ReadU64LE(log + 160);

    NativeHealthInfo health;
    health.status = criticalWarning != 0 ? "warning" : "healthy";
    health.percentage_used = percentageUsed;
    health.available_spare_percent = availableSpare;
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

  // ATA/SATA: SMART RETURN STATUS tells pass/fail; reallocated (5) and
  // pending (197) sector counts refine "healthy" vs "warning" the same
  // way the legacy PowerShell/smartctl backends do.
  constexpr DWORD kSmartDataSize = 512;
  std::vector<BYTE> buffer(sizeof(ATA_PASS_THROUGH_EX) + kSmartDataSize);
  auto* ata = reinterpret_cast<ATA_PASS_THROUGH_EX*>(buffer.data());
  ata->Length = sizeof(ATA_PASS_THROUGH_EX);
  ata->AtaFlags = ATA_FLAGS_DRDY_REQUIRED | ATA_FLAGS_DATA_IN;
  ata->DataTransferLength = kSmartDataSize;
  ata->TimeOutValue = 5;
  ata->DataBufferOffset = sizeof(ATA_PASS_THROUGH_EX);
  ata->CurrentTaskFile[0] = 0xD0;
  ata->CurrentTaskFile[1] = 0x01;
  ata->CurrentTaskFile[2] = 0x01;
  ata->CurrentTaskFile[3] = 0x4F;
  ata->CurrentTaskFile[4] = 0xC2;
  ata->CurrentTaskFile[5] = 0xA0;
  ata->CurrentTaskFile[6] = 0xB0;

  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_ATA_PASS_THROUGH, buffer.data(),
                             static_cast<DWORD>(buffer.size()), buffer.data(),
                             static_cast<DWORD>(buffer.size()), &bytesReturned, nullptr);
  CloseHandle(h);
  if (!ok) {
    result.status = NativeStorageStatus::kUnsupported;
    return result;
  }

  const BYTE* smartData = buffer.data() + sizeof(ATA_PASS_THROUGH_EX);
  bool hasReallocated = false, hasPending = false;
  for (int i = 2; i + 12 <= 362; i += 12) {
    BYTE attributeId = smartData[i];
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
  int index = ParseDriveIndex(device_id);
  if (index < 0) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  HANDLE h = OpenDrive(index, GENERIC_READ | GENERIC_WRITE);
  if (h == INVALID_HANDLE_VALUE) {
    result.status = (GetLastError() == ERROR_ACCESS_DENIED) ? NativeStorageStatus::kPermissionDenied
                                                              : NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  std::vector<BYTE> descBuf;
  STORAGE_BUS_TYPE bus = BusTypeUnknown;
  if (QueryDeviceDescriptor(h, &descBuf)) {
    bus = reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(descBuf.data())->BusType;
  }

  if (bus == BusTypeNvme) {
    std::vector<BYTE> log;
    bool ok = FetchNvmeHealthLog(h, &log);
    CloseHandle(h);
    if (!ok) {
      result.status = NativeStorageStatus::kUnsupported;
      return result;
    }

    std::vector<NativeTemperatureInfo> sensors;
    uint16_t composite = ReadU16LE(log.data() + 1);
    if (composite != 0) {
      NativeTemperatureInfo t;
      t.celsius = static_cast<double>(composite) - 273.15;
      t.sensor_id = "composite";
      t.sensor_name = "Composite";
      t.is_primary = true;
      sensors.push_back(t);
    }
    // TemperatureSensor1..8 (u16 Kelvin each) sit at byte offsets 200,
    // 202, ..., 214 in the SMART/Health Information log page (NVMe base
    // spec section 5.14.1.3, table "Health Information Log"). A value of
    // 0 means the controller does not implement that sensor.
    for (int i = 0; i < 8; i++) {
      size_t offset = 200 + i * 2;
      uint16_t kelvin = ReadU16LE(log.data() + offset);
      if (kelvin == 0) continue;
      NativeTemperatureInfo t;
      t.celsius = static_cast<double>(kelvin) - 273.15;
      t.sensor_id = "sensor" + std::to_string(i + 1);
      t.sensor_name = "Sensor " + std::to_string(i + 1);
      t.is_primary = false;
      sensors.push_back(t);
    }
    // Only worth reporting as "multiple sensors" when there is more than
    // the one composite reading [ReadTemperature] already covers.
    if (sensors.size() > 1) {
      result.value = sensors;
    } else {
      result.status = NativeStorageStatus::kUnsupported;
    }
    return result;
  }

  // ATA/SATA: attribute 194 (Temperature) and, when also present and
  // distinct, attribute 190 (Airflow Temperature) - two real, independently
  // reported sensors on many drives, not a fabricated split of one value.
  constexpr DWORD kSmartDataSize = 512;
  std::vector<BYTE> buffer(sizeof(ATA_PASS_THROUGH_EX) + kSmartDataSize);
  auto* ata = reinterpret_cast<ATA_PASS_THROUGH_EX*>(buffer.data());
  ata->Length = sizeof(ATA_PASS_THROUGH_EX);
  ata->AtaFlags = ATA_FLAGS_DRDY_REQUIRED | ATA_FLAGS_DATA_IN;
  ata->DataTransferLength = kSmartDataSize;
  ata->TimeOutValue = 5;
  ata->DataBufferOffset = sizeof(ATA_PASS_THROUGH_EX);
  ata->CurrentTaskFile[0] = 0xD0;
  ata->CurrentTaskFile[1] = 0x01;
  ata->CurrentTaskFile[2] = 0x01;
  ata->CurrentTaskFile[3] = 0x4F;
  ata->CurrentTaskFile[4] = 0xC2;
  ata->CurrentTaskFile[5] = 0xA0;
  ata->CurrentTaskFile[6] = 0xB0;

  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_ATA_PASS_THROUGH, buffer.data(),
                             static_cast<DWORD>(buffer.size()), buffer.data(),
                             static_cast<DWORD>(buffer.size()), &bytesReturned, nullptr);
  CloseHandle(h);
  if (!ok) {
    result.status = NativeStorageStatus::kUnsupported;
    return result;
  }

  const BYTE* smartData = buffer.data() + sizeof(ATA_PASS_THROUGH_EX);
  std::vector<NativeTemperatureInfo> sensors;
  for (int i = 2; i + 12 <= 362; i += 12) {
    BYTE attributeId = smartData[i];
    if (attributeId != 194 && attributeId != 190) continue;
    BYTE rawCelsius = smartData[i + 5];
    if (rawCelsius == 0) continue;
    NativeTemperatureInfo t;
    t.celsius = static_cast<double>(rawCelsius);
    t.sensor_id = std::string("smart-") + std::to_string(attributeId);
    t.sensor_name = attributeId == 194 ? "Temperature" : "Airflow Temperature";
    t.is_primary = attributeId == 194;
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

// Volume GUID paths from FindFirstVolumeW/FindNextVolumeW come back as
// "\\?\Volume{guid}\" - DeviceIoControl needs the same string with the
// trailing backslash stripped.
std::wstring TrimTrailingBackslash(const std::wstring& s) {
  if (!s.empty() && s.back() == L'\\') return s.substr(0, s.size() - 1);
  return s;
}

std::string Narrow(const std::wstring& s) {
  if (s.empty()) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0, nullptr,
                                 nullptr);
  std::string out(len, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), len, nullptr,
                       nullptr);
  return out;
}

// Which physical drive indices a volume spans, via
// IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS against the volume's own handle -
// public, documented API (winioctl.h), no WMI. A volume can span multiple
// physical disks (RAID/spanned volumes); this returns all of them so the
// caller can match against any target index.
std::vector<int> VolumeDiskIndices(const std::wstring& volumeGuidPath) {
  std::vector<int> indices;
  HANDLE h = CreateFileW(TrimTrailingBackslash(volumeGuidPath).c_str(), 0,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) return indices;

  BYTE buffer[sizeof(VOLUME_DISK_EXTENTS) + 8 * sizeof(DISK_EXTENT)] = {};
  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, nullptr, 0, buffer, sizeof(buffer),
                             &bytesReturned, nullptr);
  CloseHandle(h);
  if (!ok) return indices;

  auto* extents = reinterpret_cast<VOLUME_DISK_EXTENTS*>(buffer);
  for (DWORD i = 0; i < extents->NumberOfDiskExtents; i++) {
    indices.push_back(static_cast<int>(extents->Extents[i].DiskNumber));
  }
  return indices;
}

// First mount point ("C:\", or a mounted-folder path) for a volume GUID
// path, via GetVolumePathNamesForVolumeNameW - empty if the volume isn't
// mounted anywhere (still a real, enumerable volume, just not browsable).
std::optional<std::wstring> FirstMountPoint(const std::wstring& volumeGuidPath) {
  wchar_t buffer[4096] = {};
  DWORD needed = 0;
  if (!GetVolumePathNamesForVolumeNameW(volumeGuidPath.c_str(), buffer, ARRAYSIZE(buffer), &needed)) {
    return std::nullopt;
  }
  if (buffer[0] == L'\0') return std::nullopt;
  return std::wstring(buffer);
}

}  // namespace

std::vector<NativeVolumeInfo> StorageBackend::EnumerateVolumes(const std::string& device_id) {
  std::vector<NativeVolumeInfo> result;
  int targetIndex = ParseDriveIndex(device_id);
  if (targetIndex < 0) return result;

  wchar_t volumeName[MAX_PATH] = {};
  HANDLE findHandle = FindFirstVolumeW(volumeName, ARRAYSIZE(volumeName));
  if (findHandle == INVALID_HANDLE_VALUE) return result;

  do {
    std::wstring guidPath(volumeName);
    auto indices = VolumeDiskIndices(guidPath);
    if (std::find(indices.begin(), indices.end(), targetIndex) == indices.end()) continue;

    NativeVolumeInfo info;
    info.id = Narrow(guidPath);

    auto mount = FirstMountPoint(guidPath);
    if (mount.has_value()) {
      info.mount_point = Narrow(*mount);
      info.is_boot_volume = (_wcsicmp(mount->c_str(), L"C:\\") == 0);
    }

    wchar_t nameBuf[MAX_PATH + 1] = {};
    wchar_t fsBuf[MAX_PATH + 1] = {};
    DWORD serial = 0, maxComponentLen = 0, fsFlags = 0;
    // GetVolumeInformationW needs a path (mount point or trimmed GUID path)
    // - the trailing-backslash GUID path itself works even when unmounted.
    if (GetVolumeInformationW(guidPath.c_str(), nameBuf, ARRAYSIZE(nameBuf), &serial, &maxComponentLen,
                               &fsFlags, fsBuf, ARRAYSIZE(fsBuf))) {
      if (nameBuf[0] != L'\0') info.volume_name = Narrow(nameBuf);
      if (fsBuf[0] != L'\0') info.filesystem = Narrow(fsBuf);
      info.is_read_only = (fsFlags & FILE_READ_ONLY_VOLUME) != 0;
    }

    if (info.mount_point.has_value()) {
      ULARGE_INTEGER freeAvail, total, freeTotal;
      if (GetDiskFreeSpaceExW(mount->c_str(), &freeAvail, &total, &freeTotal)) {
        info.total_bytes = static_cast<int64_t>(total.QuadPart);
        info.free_bytes = static_cast<int64_t>(freeAvail.QuadPart);
        info.used_bytes = static_cast<int64_t>(total.QuadPart - freeTotal.QuadPart);
      }
    }

    result.push_back(std::move(info));
  } while (FindNextVolumeW(findHandle, volumeName, ARRAYSIZE(volumeName)));
  FindVolumeClose(findHandle);

  return result;
}

NativeCapacityInfo StorageBackend::GetCapacity(const std::string& device_id) {
  NativeCapacityInfo capacity;
  int index = ParseDriveIndex(device_id);
  if (index < 0) return capacity;

  HANDLE h = OpenDrive(index, 0);
  if (h != INVALID_HANDLE_VALUE) {
    GET_LENGTH_INFORMATION lengthInfo = {};
    DWORD bytesReturned = 0;
    if (DeviceIoControl(h, IOCTL_DISK_GET_LENGTH_INFO, nullptr, 0, &lengthInfo, sizeof(lengthInfo),
                         &bytesReturned, nullptr)) {
      capacity.total_bytes = lengthInfo.Length.QuadPart;
    }
    CloseHandle(h);
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

NativeResult<NativeActivityCounters> StorageBackend::ReadActivityCounters(const std::string& device_id) {
  NativeResult<NativeActivityCounters> result;
  int index = ParseDriveIndex(device_id);
  if (index < 0) {
    result.status = NativeStorageStatus::kDeviceNotFound;
    return result;
  }

  HANDLE h = OpenDrive(index, 0);
  if (h == INVALID_HANDLE_VALUE) {
    result.status = (GetLastError() == ERROR_ACCESS_DENIED) ? NativeStorageStatus::kPermissionDenied
                                                              : NativeStorageStatus::kUnsupported;
    return result;
  }

  DISK_PERFORMANCE perf = {};
  DWORD bytesReturned = 0;
  BOOL ok = DeviceIoControl(h, IOCTL_DISK_PERFORMANCE, nullptr, 0, &perf, sizeof(perf), &bytesReturned,
                             nullptr);
  CloseHandle(h);
  if (!ok) {
    result.status = NativeStorageStatus::kUnsupported;
    return result;
  }

  NativeActivityCounters counters;
  counters.bytes_read = perf.BytesRead.QuadPart;
  counters.bytes_written = perf.BytesWritten.QuadPart;
  counters.read_count = static_cast<int64_t>(perf.ReadCount);
  counters.write_count = static_cast<int64_t>(perf.WriteCount);
  counters.query_time_100ns = perf.QueryTime.QuadPart;
  counters.idle_time_100ns = perf.IdleTime.QuadPart;
  result.value = counters;
  return result;
}

}  // namespace driveguard
