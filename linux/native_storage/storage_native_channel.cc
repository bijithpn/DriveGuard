#include "storage_native_channel.h"

#include <libudev.h>

#include <algorithm>
#include <chrono>
#include <map>
#include <utility>

#include "storage_backend.h"

namespace {

// Hot-plug push notifications (Phase 7, STORAGE_MONITORING.md) via a udev
// monitor on the "block"/"disk" subsystem - the same kernel uevent source
// `udevadm monitor` reads, integrated into the GLib main loop the Flutter
// GTK embedder already runs (no extra thread). Only whole-disk ("disk"
// devtype, not "partition") add/remove uevents are forwarded; like the
// macOS/Windows equivalents this only carries a hint deviceId telling
// `MonitoringService` to re-run discovery, not a resolved "linux-<name>" id
// - matching a uevent's sysname back to our id scheme isn't necessary
// when discovery re-enumerates and diffs against the authoritative list
// either way.
struct udev* g_udev = nullptr;
struct udev_monitor* g_udev_monitor = nullptr;
guint g_udev_watch_id = 0;
FlEventChannel* g_device_events_channel = nullptr;

gboolean OnUdevReadable(GIOChannel* source, GIOCondition condition, gpointer user_data) {
  if (g_udev_monitor == nullptr) return TRUE;
  struct udev_device* dev = udev_monitor_receive_device(g_udev_monitor);
  if (dev == nullptr) return TRUE;

  const char* action = udev_device_get_action(dev);
  const char* kind = nullptr;
  if (g_strcmp0(action, "add") == 0) {
    kind = "added";
  } else if (g_strcmp0(action, "remove") == 0) {
    kind = "removed";
  }

  if (kind != nullptr && g_device_events_channel != nullptr) {
    FlValue* m = fl_value_new_map();
    fl_value_set_string_take(m, "kind", fl_value_new_string(kind));
    fl_value_set_string_take(m, "deviceId", fl_value_new_string("linux-hint"));
    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(g_device_events_channel, m, nullptr, &error)) {
      g_warning("Failed to send storage device event: %s", error->message);
    }
  }

  udev_device_unref(dev);
  return TRUE;
}

FlMethodErrorResponse* OnDeviceEventsListen(FlEventChannel* channel, FlValue* args, gpointer user_data) {
  g_udev = udev_new();
  if (g_udev == nullptr) return nullptr;  // no udev - stream just never emits, not an error.

  g_udev_monitor = udev_monitor_new_from_netlink(g_udev, "udev");
  if (g_udev_monitor == nullptr) return nullptr;

  udev_monitor_filter_add_match_subsystem_devtype(g_udev_monitor, "block", "disk");
  udev_monitor_enable_receiving(g_udev_monitor);

  GIOChannel* io = g_io_channel_unix_new(udev_monitor_get_fd(g_udev_monitor));
  g_udev_watch_id = g_io_add_watch(io, G_IO_IN, OnUdevReadable, nullptr);
  // g_io_add_watch's GSource holds its own reference to the channel; this
  // drops the caller's initial reference now that the watch owns one.
  g_io_channel_unref(io);
  return nullptr;
}

// Real-time I/O activity (Phase 8, STORAGE_MONITORING.md): polls
// /sys/block/*/stat on a GLib timeout integrated into the same main loop as
// the udev watch above (no extra thread) and diffs against the previous
// sample for a time-based rate - see StorageBackend::ReadActivityCounters.
constexpr guint kActivityIntervalMs = 1500;

FlEventChannel* g_activity_channel = nullptr;
guint g_activity_timeout_id = 0;
std::map<std::string, std::pair<driveguard::NativeActivityCounters, std::chrono::steady_clock::time_point>>
    g_activity_samples;

gboolean OnActivityTick(gpointer user_data) {
  if (g_activity_channel == nullptr) return G_SOURCE_CONTINUE;
  auto& backend = StorageBackend::Instance();
  auto now = std::chrono::steady_clock::now();

  for (const auto& device : backend.EnumerateDevices()) {
    auto counters = backend.ReadActivityCounters(device.id);
    if (!counters.has_value()) continue;

    auto it = g_activity_samples.find(device.id);
    std::optional<std::pair<driveguard::NativeActivityCounters, std::chrono::steady_clock::time_point>>
        previousSample;
    if (it != g_activity_samples.end()) previousSample = it->second;
    g_activity_samples[device.id] = {*counters, now};
    if (!previousSample.has_value()) continue;  // no prior sample to diff against yet

    const auto& previous = previousSample->first;
    double elapsedSeconds = std::chrono::duration<double>(now - previousSample->second).count();
    if (elapsedSeconds <= 0) continue;

    // Counter reset guard - see the Windows/macOS equivalents' identical
    // rationale.
    if (counters->reads_completed < previous.reads_completed ||
        counters->sectors_read < previous.sectors_read ||
        counters->writes_completed < previous.writes_completed ||
        counters->sectors_written < previous.sectors_written) {
      continue;
    }

    constexpr int64_t kBytesPerSector = 512;
    double readBytesPerSec =
        static_cast<double>((counters->sectors_read - previous.sectors_read) * kBytesPerSector) /
        elapsedSeconds;
    double writeBytesPerSec =
        static_cast<double>((counters->sectors_written - previous.sectors_written) * kBytesPerSector) /
        elapsedSeconds;
    double readOpsPerSec =
        static_cast<double>(counters->reads_completed - previous.reads_completed) / elapsedSeconds;
    double writeOpsPerSec =
        static_cast<double>(counters->writes_completed - previous.writes_completed) / elapsedSeconds;

    FlValue* m = fl_value_new_map();
    fl_value_set_string_take(m, "deviceId", fl_value_new_string(device.id.c_str()));
    fl_value_set_string_take(m, "readBytesPerSecond", fl_value_new_float(readBytesPerSec));
    fl_value_set_string_take(m, "writeBytesPerSecond", fl_value_new_float(writeBytesPerSec));
    fl_value_set_string_take(m, "readOpsPerSecond", fl_value_new_float(readOpsPerSec));
    fl_value_set_string_take(m, "writeOpsPerSecond", fl_value_new_float(writeOpsPerSec));

    if (counters->io_ms >= previous.io_ms) {
      double ioMsDelta = static_cast<double>(counters->io_ms - previous.io_ms);
      double elapsedMs = elapsedSeconds * 1000.0;
      double utilization = std::min(100.0, std::max(0.0, 100.0 * ioMsDelta / elapsedMs));
      fl_value_set_string_take(m, "utilizationPercent", fl_value_new_float(utilization));
    }

    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(g_activity_channel, m, nullptr, &error)) {
      g_warning("Failed to send storage activity event: %s", error->message);
    }
  }
  return G_SOURCE_CONTINUE;
}

FlMethodErrorResponse* OnActivityListen(FlEventChannel* channel, FlValue* args, gpointer user_data) {
  g_activity_samples.clear();
  if (g_activity_timeout_id == 0) {
    g_activity_timeout_id = g_timeout_add(kActivityIntervalMs, OnActivityTick, nullptr);
  }
  return nullptr;
}

FlMethodErrorResponse* OnActivityCancel(FlEventChannel* channel, FlValue* args, gpointer user_data) {
  if (g_activity_timeout_id != 0) {
    g_source_remove(g_activity_timeout_id);
    g_activity_timeout_id = 0;
  }
  g_activity_samples.clear();
  return nullptr;
}

FlMethodErrorResponse* OnDeviceEventsCancel(FlEventChannel* channel, FlValue* args, gpointer user_data) {
  if (g_udev_watch_id != 0) {
    g_source_remove(g_udev_watch_id);
    g_udev_watch_id = 0;
  }
  if (g_udev_monitor != nullptr) {
    udev_monitor_unref(g_udev_monitor);
    g_udev_monitor = nullptr;
  }
  if (g_udev != nullptr) {
    udev_unref(g_udev);
    g_udev = nullptr;
  }
  return nullptr;
}

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

  } else if (g_strcmp0(method, "getCapacity") == 0) {
    std::string deviceId = ArgDeviceId(args);
    auto cap = backend.GetCapacity(deviceId);
    if (!cap.total_bytes.has_value() && !cap.used_bytes.has_value()) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    } else {
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(m, "totalBytes", OptInt(cap.total_bytes));
      fl_value_set_string_take(m, "usedBytes", OptInt(cap.used_bytes));
      fl_value_set_string_take(m, "freeBytes", OptInt(cap.free_bytes));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(m));
    }

  } else if (g_strcmp0(method, "getVolumes") == 0) {
    std::string deviceId = ArgDeviceId(args);
    FlValue* list = fl_value_new_list();
    for (const auto& v : backend.EnumerateVolumes(deviceId)) {
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(m, "id", fl_value_new_string(v.id.c_str()));
      fl_value_set_string_take(m, "mountPoint", OptString(v.mount_point));
      fl_value_set_string_take(m, "filesystem", OptString(v.filesystem));
      fl_value_set_string_take(m, "isReadOnly", fl_value_new_bool(v.is_read_only));
      fl_value_set_string_take(m, "isBootVolume", fl_value_new_bool(v.is_boot_volume));
      fl_value_set_string_take(m, "totalBytes", OptInt(v.total_bytes));
      fl_value_set_string_take(m, "usedBytes", OptInt(v.used_bytes));
      fl_value_set_string_take(m, "freeBytes", OptInt(v.free_bytes));
      fl_value_append_take(list, m);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));

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

  // Intentionally leaked for the process lifetime, same rationale as
  // `channel` above.
  g_device_events_channel =
      fl_event_channel_new(messenger, "driveguard/storage_device_events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(g_device_events_channel, OnDeviceEventsListen,
                                        OnDeviceEventsCancel, nullptr, nullptr);

  g_activity_channel =
      fl_event_channel_new(messenger, "driveguard/storage_activity", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(g_activity_channel, OnActivityListen, OnActivityCancel, nullptr,
                                        nullptr);
}
