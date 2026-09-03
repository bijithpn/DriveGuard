#ifndef NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_
#define NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace driveguard {

// Registers and implements the `driveguard/storage_native` MethodChannel
// contract (docs/architecture.md "Native data contract") for Windows.
// Owns the channel for the lifetime of the main window - see
// flutter_window.cpp.
class StorageNativeChannel {
 public:
  explicit StorageNativeChannel(flutter::BinaryMessenger* messenger);
  ~StorageNativeChannel();

 private:
  static void HandleMethodCallStatic(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace driveguard

#endif  // NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_
