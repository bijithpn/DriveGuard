#include "storage_native_channel.h"

#include "storage_backend.h"

namespace {

using driveguard::NativeDeviceInfo;
using driveguard::NativeHealthInfo;
using driveguard::NativeStorageStatus;
using driveguard::StorageBackend;

FlValue* OptString(const std::optional<std::string>& s) {
  return s.has_value() && !s->empty() ? fl_value_new_string(s->c_str()) : fl_value_new_null();
}

FlValue* OptInt(const std::optional<int64_t>& v) {
  return v.has_value() ? fl_value_new_int(*v) : fl_value_new_null();
}

FlValue* DeviceToValue(const NativeDeviceInfo& d) {
  FlValue* m = fl_value_new_map();
  fl_value_set_string_take(m, "id", fl_value_new_string(d.id.c_str()));
  fl_value_set_string_take(m, "model", OptString(d.model));
  fl_value_set_string_take(m, "manufacturer", OptString(d.manufacturer));
  fl_value_set_string_take(m, "serial", OptString(d.serial));
  fl_value_set_string_take(m, "type", fl_value_new_string(d.type.c_str()));
  fl_value_set_string_take(m, "interface", fl_value_new_string(d.interface_type.c_str()));
  fl_value_set_string_take(m, "capacityBytes", OptInt(d.capacity_bytes));
  fl_value_set_string_take(m, "removable", fl_value_new_bool(d.removable));
  return m;
}

const char* StatusToErrorCode(NativeStorageStatus status) {
  switch (status) {
    case NativeStorageStatus::kPermissionDenied:
      return "PERMISSION_DENIED";
    case NativeStorageStatus::kDeviceNotFound:
      return "DEVICE_NOT_FOUND";
    default:
      return "NATIVE_ERROR";
  }
}

std::string ArgDeviceId(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return "";
  FlValue* v = fl_value_lookup_string(args, "deviceId");
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return "";
  return fl_value_get_string(v);
}

void HandleMethodCall(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  auto& backend = StorageBackend::Instance();

  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "getCapabilities") == 0) {
    FlValue* caps = fl_value_new_map();
    fl_value_set_string_take(caps, "backendName",
                              fl_value_new_string("Linux (sysfs + NVMe/ATA ioctl native)"));
    fl_value_set_string_take(caps, "canEnumerateDevices", fl_value_new_bool(TRUE));
    fl_value_set_string_take(caps, "canReadTemperature", fl_value_new_bool(TRUE));
    fl_value_set_string_take(caps, "canReadHealth", fl_value_new_bool(TRUE));
    fl_value_set_string_take(caps, "missingTools", fl_value_new_list());
    FlValue* notes = fl_value_new_list();
    fl_value_append_take(
        notes, fl_value_new_string(
                   "Reads /sys/block + /sys/class/hwmon directly and issues NVMe_IOCTL_ADMIN_CMD "
                   "(Get Log Page) / HDIO_DRIVE_CMD (SMART) - no smartctl/nvme-cli subprocess "
                   "required when the kernel and permissions allow it."));
    fl_value_append_take(
        notes,
        fl_value_new_string(
            "NVMe admin commands and some SATA SMART ioctls require root or a udev rule granting "
            "access to /dev/nvme* or /dev/sd*; without it, temperature/health fall back to "
            "nvme-cli/smartctl (see docs/permissions.md)."));
    fl_value_set_string_take(caps, "notes", notes);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(caps));

  } else if (g_strcmp0(method, "getDevices") == 0) {
    FlValue* list = fl_value_new_list();
    for (const auto& d : backend.EnumerateDevices()) {
      fl_value_append_take(list, DeviceToValue(d));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));

  } else if (g_strcmp0(method, "readTemperature") == 0) {
    std::string deviceId = ArgDeviceId(args);
    auto r = backend.ReadTemperature(deviceId);
    if (r.status == NativeStorageStatus::kOk && r.value.has_value()) {
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(m, "celsius", fl_value_new_float(r.value->celsius));
      fl_value_set_string_take(m, "sensorId", fl_value_new_string(r.value->sensor_id.c_str()));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(m));
    } else if (r.status == NativeStorageStatus::kUnsupported) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new(StatusToErrorCode(r.status), r.message.c_str(), nullptr));
    }

  } else if (g_strcmp0(method, "getSensors") == 0) {
    std::string deviceId = ArgDeviceId(args);
    auto r = backend.ReadSensors(deviceId);
    if (r.status == NativeStorageStatus::kOk && r.value.has_value()) {
      FlValue* list = fl_value_new_list();
      for (const auto& s : *r.value) {
        FlValue* m = fl_value_new_map();
        fl_value_set_string_take(m, "id", fl_value_new_string(s.sensor_id.c_str()));
        fl_value_set_string_take(m, "name", fl_value_new_string(s.sensor_name.c_str()));
        fl_value_set_string_take(m, "celsius", fl_value_new_float(s.celsius));
        fl_value_set_string_take(m, "isPrimary", fl_value_new_bool(s.is_primary));
        fl_value_append_take(list, m);
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
    } else if (r.status == NativeStorageStatus::kUnsupported) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_list()));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new(StatusToErrorCode(r.status), r.message.c_str(), nullptr));
    }

  } else if (g_strcmp0(method, "getHealth") == 0) {
    std::string deviceId = ArgDeviceId(args);
    auto r = backend.ReadHealth(deviceId);
    if (r.status == NativeStorageStatus::kOk && r.value.has_value()) {
      const auto& h = *r.value;
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(m, "status", fl_value_new_string(h.status.c_str()));
      fl_value_set_string_take(
          m, "percentageUsed",
          h.percentage_used.has_value() ? fl_value_new_int(*h.percentage_used) : fl_value_new_null());
      fl_value_set_string_take(m, "availableSparePercent",
                                h.available_spare_percent.has_value()
                                    ? fl_value_new_int(*h.available_spare_percent)
                                    : fl_value_new_null());
      fl_value_set_string_take(m, "criticalWarning", OptString(h.critical_warning));
      fl_value_set_string_take(m, "mediaErrors", OptInt(h.media_errors));
      fl_value_set_string_take(m, "powerCycles", OptInt(h.power_cycles));
      fl_value_set_string_take(m, "powerOnHours", OptInt(h.power_on_hours));
      fl_value_set_string_take(m, "unsafeShutdowns", OptInt(h.unsafe_shutdowns));
      if (h.smart_passed.has_value()) {
        fl_value_set_string_take(m, "smartPassed", fl_value_new_bool(*h.smart_passed));
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(m));
    } else if (r.status == NativeStorageStatus::kUnsupported) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new(StatusToErrorCode(r.status), r.message.c_str(), nullptr));
    }

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to storage_native method call: %s", error->message);
  }
}

}  // namespace

void storage_native_channel_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Intentionally leaked for the process lifetime, matching how
  // generated_plugin_registrant.cc keeps plugin registrar objects alive -
  // there is exactly one of these per process and it must outlive every
  // Dart call into it.
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, "driveguard/storage_native", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, HandleMethodCall, nullptr, nullptr);
}
