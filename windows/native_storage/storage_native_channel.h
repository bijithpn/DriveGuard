#ifndef NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_
#define NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <map>
#include <memory>
#include <string>

#include "storage_backend.h"

namespace driveguard {

// Registers and implements the `driveguard/storage_native` MethodChannel
// contract (docs/architecture.md "Native data contract") for Windows.
// Owns the channel for the lifetime of the main window - see
// flutter_window.cpp.
//
// Also registers the `driveguard/storage_device_events` EventChannel (Phase
// 7, STORAGE_MONITORING.md): a hidden HWND_MESSAGE window receives
// WM_DEVICECHANGE via RegisterDeviceNotification for GUID_DEVINTERFACE_DISK
// - the same public notification mechanism Explorer uses for "a drive was
// plugged in" - and pushes a `{"kind": "added"|"removed", "deviceId": "windows-hint"}`
// event that only tells `MonitoringService` to re-run discovery; it does not
// attempt to resolve the exact PhysicalDriveN index from the notification
// (DBT_DEVICEARRIVAL for a disk interface doesn't reliably carry one), so
// the "deviceId" is a hint, not a real device id - discovery re-enumerates
// and diffs against the authoritative getDevices() list either way.
class StorageNativeChannel {
 public:
  explicit StorageNativeChannel(flutter::BinaryMessenger* messenger);
  ~StorageNativeChannel();

 private:
  static void HandleMethodCallStatic(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SetupDeviceEvents(flutter::BinaryMessenger* messenger);
  void TeardownDeviceEvents();
  void SetupActivityStream(flutter::BinaryMessenger* messenger);

  static LRESULT CALLBACK WndProcStatic(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void OnActivityTimerTick();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> activity_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> activity_sink_;
  HWND notify_window_ = nullptr;
  HDEVNOTIFY device_notify_ = nullptr;

  // Previous IOCTL_DISK_PERFORMANCE sample per device id, for the
  // time-based-delta rate calculation - see storage_backend.cpp's
  // ReadActivityCounters header comment.
  std::map<std::string, std::pair<NativeActivityCounters, std::chrono::steady_clock::time_point>>
      activity_samples_;
};

}  // namespace driveguard

#endif  // NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_
