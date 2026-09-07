// DriveGuard Windows 11 Widgets Board provider - SCAFFOLD, UNBUILT.
//
// Not wired into windows/CMakeLists.txt on purpose: this cannot compile or
// link as-is inside the existing unpackaged Flutter runner target. Widgets
// Board providers are out-of-process COM servers that only Windows'
// Widget Service can activate, and only for an MSIX-packaged app - see
// README.md in this folder for what a real integration needs (a separate
// packaging project, Windows App SDK, a manifest COM/extension
// registration). This file exists so that work has a concrete starting
// point instead of a blank page.
//
// Data contract: reads the same JSON file NativeWidgetBridge (Dart side,
// see lib/infrastructure/native/native_widget_bridge.dart) writes on every
// device/activity change:
//   %LOCALAPPDATA%\<APPLICATION_ID>\driveguard\widget_snapshot.json
// (APPLICATION_ID is whatever windows/CMakeLists.txt / the app's identity
// resolves to via path_provider's getApplicationSupportDirectory()).
//
// This provider never talks to the running DriveGuard process directly -
// same design as the macOS WidgetKit extension and the GNOME Shell
// extension: read-only, file-watching, independent lifecycle.

#pragma once

#include <winrt/Microsoft.Windows.Widgets.Providers.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Search.h>
#include <string>
#include <unordered_map>

namespace winrt::DriveGuardWidgetProvider::implementation
{
    using namespace winrt::Microsoft::Windows::Widgets::Providers;

    // Implements IWidgetProvider: the four calls the Widget Service makes
    // into a provider (create/activate/deactivate/delete). One process can
    // host multiple simultaneous widget instances (e.g. pinned twice), so
    // state is tracked per widgetId.
    struct WidgetProvider : winrt::implements<WidgetProvider, IWidgetProvider>
    {
        WidgetProvider();

        // IWidgetProvider
        void CreateWidget(WidgetContext const& context);
        void Activate(WidgetContext const& context);
        void Deactivate(winrt::hstring const& widgetId);
        void DeleteWidget(winrt::hstring const& widgetId, winrt::hstring const& customState);
        void OnActionInvoked(WidgetActionInvokedArgs const& args);
        void OnWidgetContextChanged(WidgetContextChangedArgs const& args);

    private:
        // Renders the current snapshot file as an Adaptive Card JSON string
        // (see widget_template.json for the static structure this fills in)
        // and calls WidgetManager::UpdateWidget for every active widgetId.
        winrt::hstring RenderCardJson();
        void PushUpdateToAllActive();
        std::wstring SnapshotFilePath();

        std::unordered_map<winrt::hstring, WidgetContext> m_activeWidgets;
    };
}
