#ifndef NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_
#define NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Registers the `driveguard/storage_native` MethodChannel contract
// (docs/architecture.md "Native data contract") against the given Flutter
// engine's binary messenger. Called once from my_application.cc after the
// FlView is created; the channel is kept alive for the process lifetime
// (registered against a static-lifetime binary messenger owned by the
// engine), matching how generated_plugin_registrant.cc registers plugins.
void storage_native_channel_register(FlBinaryMessenger* messenger);

#endif  // NATIVE_STORAGE_STORAGE_NATIVE_CHANNEL_H_
