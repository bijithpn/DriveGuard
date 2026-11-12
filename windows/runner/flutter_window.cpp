#include "flutter_window.h"

#include <optional>
#include <shobjidl_core.h>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

// Floating windows (edge dock, mini widget) should follow the user across
// virtual desktops like they do across macOS Spaces. Windows has no public
// "pin to all desktops" call, so poll: when such a window is not on the
// current desktop, move it to the desktop of any visible window that is.
struct DesktopProbe {
  IVirtualDesktopManager* manager;
  HWND self;
  GUID desktop;
  bool found;
};

BOOL CALLBACK FindCurrentDesktop(HWND hwnd, LPARAM param) {
  auto* probe = reinterpret_cast<DesktopProbe*>(param);
  if (hwnd == probe->self || !::IsWindowVisible(hwnd) || ::IsIconic(hwnd)) {
    return TRUE;
  }
  BOOL on_current = FALSE;
  if (SUCCEEDED(probe->manager->IsWindowOnCurrentVirtualDesktop(
          hwnd, &on_current)) &&
      on_current &&
      SUCCEEDED(probe->manager->GetWindowDesktopId(hwnd, &probe->desktop))) {
    probe->found = true;
    return FALSE;
  }
  return TRUE;
}

void CALLBACK FollowVirtualDesktop(HWND child, UINT, UINT_PTR, DWORD) {
  static IVirtualDesktopManager* manager = [] {
    IVirtualDesktopManager* m = nullptr;
    ::CoCreateInstance(__uuidof(VirtualDesktopManager), nullptr, CLSCTX_ALL,
                       IID_PPV_ARGS(&m));
    return m;
  }();
  HWND window = ::GetAncestor(child, GA_ROOT);
  if (!manager || !window || !::IsWindowVisible(window)) return;
  BOOL on_current = TRUE;
  if (FAILED(manager->IsWindowOnCurrentVirtualDesktop(window, &on_current)) ||
      on_current) {
    return;
  }
  DesktopProbe probe{manager, window, {}, false};
  ::EnumWindows(FindCurrentDesktop, reinterpret_cast<LPARAM>(&probe));
  if (probe.found) manager->MoveWindowToDesktop(window, probe.desktop);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  storage_native_channel_ = std::make_unique<driveguard::StorageNativeChannel>(
      flutter_controller_->engine()->messenger());

  // The mini-widget window (see DesktopWindowController/MiniWidgetApp in
  // Dart) is a genuinely separate FlutterViewController/engine created by
  // desktop_multi_window, not a reshaped main window. It needs its own
  // plugin registrations - notably window_manager, so that window sets its
  // own frameless/always-on-top/position independent of the main dashboard
  // window - which only happens via this callback.
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    RegisterPlugins(flutter_view_controller->engine());
    ::SetTimer(flutter_view_controller->view()->GetNativeWindow(), 1, 250,
               FollowVirtualDesktop);
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
