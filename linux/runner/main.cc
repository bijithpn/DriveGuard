#include "my_application.h"

#include <gdk/gdk.h>
#include <stdlib.h>

int main(int argc, char** argv) {
  // Wayland compositors ignore an app's requests to position its own windows,
  // stay on top, or draw transparent borderless windows - all of which the
  // edge dock and mini widget depend on. Prefer the X11 backend (XWayland on a
  // Wayland session), where those work. Set DRIVEGUARD_WAYLAND=1 to opt out.
  if (getenv("DRIVEGUARD_WAYLAND") == nullptr && getenv("GDK_BACKEND") == nullptr &&
      getenv("DISPLAY") != nullptr) {
    gdk_set_allowed_backends("x11,*");
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
