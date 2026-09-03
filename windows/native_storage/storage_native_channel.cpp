#include "storage_native_channel.h"

#include <dbt.h>

#include "storage_backend.h"

namespace driveguard {

namespace {

// GUID_DEVINTERFACE_DISK, defined locally by value (rather than pulling in
// ntddstor.h's INITGUID/link dependency) so RegisterDeviceNotification can
// filter to disk device interfaces specifically instead of every device
// class change.
constexpr GUID kGuidDevInterfaceDisk = {
    0x53f56307, 0xb6bf, 0x11d0, {0x94, 0xf2, 0x00, 0xa0, 0xc9, 0x1e, 0xfb, 0x8b}};

constexpr wchar_t kNotifyWindowClassName[] = L"DriveGuardStorageDeviceNotifyWindow";

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

  SetupDeviceEvents(messenger);
}

StorageNativeChannel::~StorageNativeChannel() { TeardownDeviceEvents(); }

void StorageNativeChannel::SetupDeviceEvents(flutter::BinaryMessenger* messenger) {
  WNDCLASSW wc = {};
  wc.lpfnWndProc = &StorageNativeChannel::WndProcStatic;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kNotifyWindowClassName;
  // RegisterClassW fails harmlessly if already registered (e.g. a second
  // StorageNativeChannel instance, which doesn't happen in practice but
  // shouldn't crash if it did) - ignore the return value.
  RegisterClassW(&wc);

  notify_window_ = CreateWindowExW(0, kNotifyWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                    GetModuleHandleW(nullptr), this);
  if (notify_window_ != nullptr) {
    DEV_BROADCAST_DEVICEINTERFACE filter = {};
    filter.dbcc_size = sizeof(filter);
    filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
    filter.dbcc_classguid = kGuidDevInterfaceDisk;
    device_notify_ = RegisterDeviceNotificationW(notify_window_, &filter, DEVICE_NOTIFY_WINDOW_HANDLE);
  }

  event_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, "driveguard/storage_device_events", &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            event_sink_.reset();
            return nullptr;
          }));
}

void StorageNativeChannel::TeardownDeviceEvents() {
  if (device_notify_ != nullptr) {
    UnregisterDeviceNotification(device_notify_);
    device_notify_ = nullptr;
  }
  if (notify_window_ != nullptr) {
    DestroyWindow(notify_window_);
    notify_window_ = nullptr;
  }
  event_sink_.reset();
}

LRESULT CALLBACK StorageNativeChannel::WndProcStatic(HWND hwnd, UINT message, WPARAM wparam,
                                                       LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* createStruct = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(createStruct->lpCreateParams));
  }
  auto* self = reinterpret_cast<StorageNativeChannel*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    return self->HandleWindowMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT StorageNativeChannel::HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_DEVICECHANGE &&
      (wparam == DBT_DEVICEARRIVAL || wparam == DBT_DEVICEREMOVECOMPLETE)) {
    auto* header = reinterpret_cast<DEV_BROADCAST_HDR*>(lparam);
    if (header != nullptr && header->dbch_devicetype == DBT_DEVTYP_DEVICEINTERFACE && event_sink_) {
      EncodableMap event;
      event[EncodableValue("kind")] =
          EncodableValue(std::string(wparam == DBT_DEVICEARRIVAL ? "added" : "removed"));
      // No reliable PhysicalDriveN index in a disk-interface arrival/removal
      // broadcast - this is a rediscovery hint, see the header comment.
      event[EncodableValue("deviceId")] = EncodableValue(std::string("windows-hint"));
      event_sink_->Success(EncodableValue(event));
    }
    return TRUE;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

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

  if (call.method_name() == "getCapacity") {
    auto cap = backend.GetCapacity(deviceId);
    if (!cap.total_bytes.has_value() && !cap.used_bytes.has_value()) {
      result->Success(EncodableValue());
      return;
    }
    EncodableMap m;
    m[EncodableValue("totalBytes")] = OptInt(cap.total_bytes);
    m[EncodableValue("usedBytes")] = OptInt(cap.used_bytes);
    m[EncodableValue("freeBytes")] = OptInt(cap.free_bytes);
    result->Success(EncodableValue(m));
    return;
  }

  if (call.method_name() == "getVolumes") {
    EncodableList list;
    for (const auto& v : backend.EnumerateVolumes(deviceId)) {
      EncodableMap m;
      m[EncodableValue("id")] = EncodableValue(v.id);
      m[EncodableValue("mountPoint")] = OptString(v.mount_point);
      m[EncodableValue("volumeName")] = OptString(v.volume_name);
      m[EncodableValue("filesystem")] = OptString(v.filesystem);
      m[EncodableValue("isReadOnly")] = EncodableValue(v.is_read_only);
      m[EncodableValue("isBootVolume")] = EncodableValue(v.is_boot_volume);
      m[EncodableValue("totalBytes")] = OptInt(v.total_bytes);
      m[EncodableValue("usedBytes")] = OptInt(v.used_bytes);
      m[EncodableValue("freeBytes")] = OptInt(v.free_bytes);
      list.push_back(EncodableValue(m));
    }
    result->Success(EncodableValue(list));
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
