import WidgetKit
import SwiftUI

// MARK: - Shared data contract
//
// The main app (see lib/infrastructure/native/native_widget_bridge.dart)
// pushes a snapshot of the drive list to this App Group's UserDefaults
// every time the data changes, then asks WidgetKit to reload. This file
// only *reads* that snapshot - it never talks to the running app directly,
// so the widget keeps rendering the last known data even if the main app
// isn't running.
//
// macOS (unlike iOS) requires the group id to start with the signing
// Team ID (PUA3NSL244 - Jithin Wails) rather than a literal "group."
// prefix. Must match NativeWidgetChannel.swift's appGroupId and both
// entitlements files.
let kAppGroupId = "PUA3NSL244.driveguard.widget"
let kSnapshotKey = "driveguard.snapshot"

struct WidgetDeviceSnapshot: Decodable {
  let id: String
  let name: String
  let valueText: String
  let fraction: Double
  let severity: String // "normal" | "warning" | "critical"
}

struct WidgetSnapshotPayload: Decodable {
  let devices: [WidgetDeviceSnapshot]
  let updatedAt: String?
}

func loadSnapshot() -> [WidgetDeviceSnapshot] {
  guard let defaults = UserDefaults(suiteName: kAppGroupId),
        let json = defaults.string(forKey: kSnapshotKey),
        let data = json.data(using: .utf8) else {
    return []
  }
  return (try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data))?.devices ?? []
}

// MARK: - Timeline

struct DriveEntry: TimelineEntry {
  let date: Date
  let devices: [WidgetDeviceSnapshot]
}

struct DriveProvider: TimelineProvider {
  func placeholder(in context: Context) -> DriveEntry {
    DriveEntry(date: Date(), devices: [
      WidgetDeviceSnapshot(id: "preview", name: "NVMe SSD", valueText: "47°C", fraction: 0.5, severity: "normal"),
    ])
  }

  func getSnapshot(in context: Context, completion: @escaping (DriveEntry) -> Void) {
    completion(DriveEntry(date: Date(), devices: loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DriveEntry>) -> Void) {
    let entry = DriveEntry(date: Date(), devices: loadSnapshot())
    // The app pushes a fresh snapshot + WidgetCenter.reloadAllTimelines()
    // on every change, so this fallback refresh just guards against the
    // app being closed for a while (e.g. it crashed) - refresh hourly.
    let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }
}

// MARK: - View

private func severityColor(_ severity: String) -> Color {
  switch severity {
  case "critical": return .red
  case "warning": return .orange
  default: return .green
  }
}

struct DriveGuardWidgetView: View {
  var entry: DriveProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("DriveGuard")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
      if entry.devices.isEmpty {
        Spacer()
        Text("No drives")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Spacer()
      } else {
        ForEach(entry.devices.prefix(4), id: \.id) { device in
          HStack {
            Circle()
              .fill(severityColor(device.severity))
              .frame(width: 6, height: 6)
            Text(device.name)
              .font(.footnote)
              .lineLimit(1)
            Spacer()
            Text(device.valueText)
              .font(.footnote.monospacedDigit())
              .fontWeight(.medium)
          }
        }
      }
    }
    .padding(12)
    .containerBackground(.background, for: .widget)
  }
}

struct DriveGuardWidget: Widget {
  let kind: String = "DriveGuardWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: DriveProvider()) { entry in
      DriveGuardWidgetView(entry: entry)
    }
    .configurationDisplayName("DriveGuard")
    .description("Live drive temperature and health at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
