// See WidgetProvider.h for status/scope notes. UNBUILT scaffold.

#include "WidgetProvider.h"
#include <winrt/Microsoft.Windows.Widgets.h>
#include <winrt/Windows.Data.Json.h>
#include <fstream>
#include <sstream>
#include <cstdlib>

using namespace winrt;
using namespace winrt::Microsoft::Windows::Widgets;
using namespace winrt::Microsoft::Windows::Widgets::Providers;
using namespace winrt::Windows::Data::Json;

namespace winrt::DriveGuardWidgetProvider::implementation
{
    WidgetProvider::WidgetProvider() = default;

    std::wstring WidgetProvider::SnapshotFilePath()
    {
        // TODO: replace L"com.example.driveguard" with whatever
        // getApplicationId()/APPLICATION_ID actually resolves to once this
        // is wired up for real - see the note in WidgetProvider.h.
        wchar_t* localAppData = nullptr;
        size_t len = 0;
        if (_wdupenv_s(&localAppData, &len, L"LOCALAPPDATA") != 0 || !localAppData)
        {
            return L"";
        }
        std::wstring path = std::wstring(localAppData) +
            L"\\com.example.driveguard\\driveguard\\widget_snapshot.json";
        free(localAppData);
        return path;
    }

    winrt::hstring WidgetProvider::RenderCardJson()
    {
        std::wifstream file(SnapshotFilePath());
        if (!file.is_open())
        {
            // No snapshot yet (DriveGuard never run, or file mid-write) -
            // render an empty-state card rather than fail the update.
            return L"{\"type\":\"AdaptiveCard\",\"version\":\"1.5\",\"body\":"
                   L"[{\"type\":\"TextBlock\",\"text\":\"DriveGuard\",\"weight\":\"Bolder\"},"
                   L"{\"type\":\"TextBlock\",\"text\":\"No data yet\",\"isSubtle\":true}]}";
        }
        std::wstringstream buffer;
        buffer << file.rdbuf();

        JsonObject snapshot;
        if (!JsonObject::TryParse(buffer.str(), snapshot))
        {
            return L"{\"type\":\"AdaptiveCard\",\"version\":\"1.5\",\"body\":"
                   L"[{\"type\":\"TextBlock\",\"text\":\"DriveGuard - bad data\"}]}";
        }

        // Build a FactSet-based card: one row per drive, "Name" -> "temp".
        // See widget_template.json for the fuller static reference layout;
        // this keeps the runtime version minimal and dependency-free.
        JsonArray facts;
        auto devices = snapshot.GetNamedArray(L"devices", JsonArray());
        for (auto const& item : devices)
        {
            auto device = item.GetObject();
            JsonObject fact;
            fact.SetNamedValue(L"title", JsonValue::CreateStringValue(device.GetNamedString(L"name", L"Drive")));
            fact.SetNamedValue(L"value", JsonValue::CreateStringValue(device.GetNamedString(L"valueText", L"—")));
            facts.Append(fact);
        }

        JsonObject factSet;
        factSet.SetNamedValue(L"type", JsonValue::CreateStringValue(L"FactSet"));
        factSet.SetNamedValue(L"facts", facts);

        JsonObject title;
        title.SetNamedValue(L"type", JsonValue::CreateStringValue(L"TextBlock"));
        title.SetNamedValue(L"text", JsonValue::CreateStringValue(L"DriveGuard"));
        title.SetNamedValue(L"weight", JsonValue::CreateStringValue(L"Bolder"));

        JsonArray body;
        body.Append(title);
        body.Append(facts.Size() > 0 ? factSet : JsonObject());

        JsonObject card;
        card.SetNamedValue(L"type", JsonValue::CreateStringValue(L"AdaptiveCard"));
        card.SetNamedValue(L"version", JsonValue::CreateStringValue(L"1.5"));
        card.SetNamedValue(L"body", body);

        return card.Stringify();
    }

    void WidgetProvider::PushUpdateToAllActive()
    {
        auto manager = WidgetManager::GetDefault();
        auto cardJson = RenderCardJson();
        for (auto const& [widgetId, context] : m_activeWidgets)
        {
            WidgetUpdateRequestOptions options(widgetId);
            options.Template(cardJson);
            options.Data(cardJson);
            manager.UpdateWidget(options);
        }
    }

    void WidgetProvider::CreateWidget(WidgetContext const& context)
    {
        m_activeWidgets[context.Id()] = context;
        PushUpdateToAllActive();
        // A real implementation should also start a file-watch
        // (ReadDirectoryChangesW or Windows.Storage FolderChangeTracker) on
        // the snapshot's directory here and call PushUpdateToAllActive()
        // whenever it fires, rather than only updating on
        // create/activate/context-change.
    }

    void WidgetProvider::Activate(WidgetContext const& context)
    {
        m_activeWidgets[context.Id()] = context;
        PushUpdateToAllActive();
    }

    void WidgetProvider::Deactivate(winrt::hstring const& widgetId)
    {
        m_activeWidgets.erase(widgetId);
    }

    void WidgetProvider::DeleteWidget(winrt::hstring const& widgetId, winrt::hstring const&)
    {
        m_activeWidgets.erase(widgetId);
    }

    void WidgetProvider::OnActionInvoked(WidgetActionInvokedArgs const&)
    {
        // No interactive actions defined on the card yet (e.g. "Open
        // DriveGuard" / "Rescan"). Wire up Adaptive Card Action.Execute
        // verbs here if you add any.
    }

    void WidgetProvider::OnWidgetContextChanged(WidgetContextChangedArgs const& args)
    {
        m_activeWidgets[args.WidgetContext().Id()] = args.WidgetContext();
        PushUpdateToAllActive();
    }
}
