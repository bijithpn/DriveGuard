#include "storage_native_channel.h"

#include "storage_backend.h"

namespace driveguard {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

EncodableValue OptString(const std::optional<std::string>& s) {
  return s.has_value() ? EncodableValue(*s) : EncodableValue();
}

EncodableValue OptInt(const std::optional<int64_t>& v) {
  return v.has_value() ? EncodableValue(*v) : EncodableValue();
}

EncodableValue DeviceToMap(const NativeDeviceInfo& d) {
  EncodableMap m;
  m[EncodableValue("id")] = EncodableValue(d.id);
  m[EncodableValue("model")] = EncodableValue(d.model);
  m[EncodableValue("manufacturer")] = EncodableValue(d.manufacturer);
  m[EncodableValue("serial")] = EncodableValue(d.serial);
  m[EncodableValue("type")] = EncodableValue(d.type);
  m[EncodableValue("interface")] = EncodableValue(d.interface_type);
  m[EncodableValue("capacityBytes")] = OptInt(d.capacity_bytes);
  m[EncodableValue("removable")] = EncodableValue(d.removable);
  return EncodableValue(m);
}

// Maps a non-Ok [NativeStorageStatus] to the PlatformException code the
// Dart `StorageNativeChannel` wrapper understands. kOk/kUnsupported are
// handled by the caller (success value or bare null), never reach here.
std::string StatusToErrorCode(NativeStorageStatus status) {
  switch (status) {
    case NativeStorageStatus::kPermissionDenied:
      return "PERMISSION_DENIED";
    case NativeStorageStatus::kDeviceNotFound:
      return "DEVICE_NOT_FOUND";
    default:
      return "NATIVE_ERROR";
  }
}

}  // namespace

StorageNativeChannel::StorageNativeChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "driveguard/storage_native", &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [](const auto& call, auto result) { StorageNativeChannel::HandleMethodCallStatic(call, std::move(result)); });
}

StorageNativeChannel::~StorageNativeChannel() = default;

// static-equivalent dispatcher kept as a free function bound via lambda
// above so the channel can be cheaply constructed without exposing a
// public static from the header; declared here to keep this file
// self-contained.
namespace {
void DispatchMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto& backend = StorageBackend::Instance();

  if (call.method_name() == "getCapabilities") {
    EncodableMap caps;
    caps[EncodableValue("backendName")] =
        EncodableValue(std::string("Windows (DeviceIoControl native)"));
    caps[EncodableValue("canEnumerateDevices")] = EncodableValue(true);
    caps[EncodableValue("canReadTemperature")] = EncodableValue(true);
    caps[EncodableValue("canReadHealth")] = EncodableValue(true);
    caps[EncodableValue("missingTools")] = EncodableValue(EncodableList{});
    caps[EncodableValue("notes")] = EncodableValue(EncodableList{
        EncodableValue(std::string(
            "Reads NVMe SMART/Health log pages and ATA SMART attributes directly via "
            "IOCTL_STORAGE_QUERY_PROPERTY / IOCTL_ATA_PASS_THROUGH - no PowerShell, no WMI.")),
        EncodableValue(std::string(
            "Not yet verified on physical Windows hardware in this development environment - "
            "see docs/windows-telemetry.md.")),
        EncodableValue(std::string(
            "USB bridges that don't pass ATA_PASS_THROUGH through will report temperature/health "
            "as unavailable; the legacy PowerShell backend is tried as a further fallback."))});
    result->Success(EncodableValue(caps));
    return;
  }

  if (call.method_name() == "getDevices") {
    EncodableList list;
    for (const auto& d : backend.EnumerateDevices()) {
      list.push_back(DeviceToMap(d));
    }
    result->Success(EncodableValue(list));
    return;
  }

  const auto* args = std::get_if<EncodableMap>(call.arguments());
  std::string deviceId;
  if (args) {
    auto it = args->find(EncodableValue("deviceId"));
    if (it != args->end()) {
      if (const auto* s = std::get_if<std::string>(&it->second)) deviceId = *s;
    }
  }

  if (call.method_name() == "readTemperature") {
    auto r = backend.ReadTemperature(deviceId);
    if (r.status == NativeStorageStatus::kOk && r.value.has_value()) {
      EncodableMap m;
      m[EncodableValue("celsius")] = EncodableValue(r.value->celsius);
      m[EncodableValue("sensorId")] = EncodableValue(r.value->sensor_id);
      result->Success(EncodableValue(m));
    } else if (r.status == NativeStorageStatus::kUnsupported) {
      result->Success(EncodableValue());
    } else {
      result->Error(StatusToErrorCode(r.status), r.message);
    }
    return;
  }

  if (call.method_name() == "getSensors") {
    auto r = backend.ReadSensors(deviceId);
    if (r.status == NativeStorageStatus::kOk && r.value.has_value()) {
      EncodableList list;
      for (const auto& s : *r.value) {
        EncodableMap m;
        m[EncodableValue("id")] = EncodableValue(s.sensor_id);
        m[EncodableValue("name")] = EncodableValue(s.sensor_name);
        m[EncodableValue("celsius")] = EncodableValue(s.celsius);
        m[EncodableValue("isPrimary")] = EncodableValue(s.is_primary);
        list.push_back(EncodableValue(m));
      }
      result->Success(EncodableValue(list));
    } else if (r.status == NativeStorageStatus::kUnsupported) {
      result->Success(EncodableValue(EncodableList{}));
    } else {
      result->Error(StatusToErrorCode(r.status), r.message);
    }
    return;
  }

  if (call.method_name() == "getHealth") {
    auto r = backend.ReadHealth(deviceId);
    if (r.status == NativeStorageStatus::kOk && r.value.has_value()) {
      const auto& h = *r.value;
      EncodableMap m;
      m[EncodableValue("status")] = EncodableValue(h.status);
      m[EncodableValue("percentageUsed")] = OptInt(h.percentage_used ? std::optional<int64_t>(*h.percentage_used) : std::nullopt);
      m[EncodableValue("availableSparePercent")] = OptInt(h.available_spare_percent ? std::optional<int64_t>(*h.available_spare_percent) : std::nullopt);
      m[EncodableValue("criticalWarning")] = OptString(h.critical_warning);
      m[EncodableValue("mediaErrors")] = OptInt(h.media_errors);
      m[EncodableValue("powerCycles")] = OptInt(h.power_cycles);
      m[EncodableValue("powerOnHours")] = OptInt(h.power_on_hours);
      m[EncodableValue("unsafeShutdowns")] = OptInt(h.unsafe_shutdowns);
      if (h.smart_passed.has_value()) {
        m[EncodableValue("smartPassed")] = EncodableValue(*h.smart_passed);
      }
      result->Success(EncodableValue(m));
    } else if (r.status == NativeStorageStatus::kUnsupported) {
      result->Success(EncodableValue());
    } else {
      result->Error(StatusToErrorCode(r.status), r.message);
    }
    return;
  }

  result->NotImplemented();
}
}  // namespace

void StorageNativeChannel::HandleMethodCallStatic(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  DispatchMethodCall(call, std::move(result));
}

}  // namespace driveguard
