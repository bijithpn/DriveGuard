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
  let severity: String // "normal" | "warning" | "critical" | "unavailable"
  let type: String? // "nvme" | "ssd" | "hdd" | "unknown"
  let healthStatus: String?
  let lifePercent: Int?
  let freeCapacityText: String?
}

struct WidgetSnapshotPayload: Decodable {
  let devices: [WidgetDeviceSnapshot]
  let updatedAt: String?
}

func loadSnapshot() -> WidgetSnapshotPayload? {
  guard let defaults = UserDefaults(suiteName: kAppGroupId),
        let json = defaults.string(forKey: kSnapshotKey),
        let data = json.data(using: .utf8) else {
    return nil
  }
  return try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data)
}

// MARK: - Severity

/// Central place for severity → color/icon/label so every view (small,
/// medium, large, header badge, per-row badge) renders warning/critical
/// identically instead of each view inventing its own mapping.
enum Severity: String {
  case critical, warning, normal, unavailable

  init(_ raw: String) {
    self = Severity(rawValue: raw) ?? .unavailable
  }

  /// Ordering for "pick the worst device" - higher wins.
  var rank: Int {
    switch self {
    case .critical: return 3
    case .warning: return 2
    case .normal: return 1
    case .unavailable: return 0
    }
  }

  var color: Color {
    switch self {
    case .critical: return Color(red: 1.0, green: 0.33, blue: 0.33)
    case .warning: return Color(red: 1.0, green: 0.69, blue: 0.24)
    case .normal: return Color(red: 0.30, green: 0.82, blue: 0.44)
    case .unavailable: return .secondary
    }
  }

  var icon: String {
    switch self {
    case .critical: return "xmark.octagon.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .normal: return "checkmark.circle.fill"
    case .unavailable: return "questionmark.circle.fill"
    }
  }

  var label: String {
    switch self {
    case .critical: return "Critical"
    case .warning: return "Warning"
    case .normal: return "Normal"
    case .unavailable: return "No data"
    }
  }
}

private func deviceIcon(_ type: String?) -> String {
  switch type {
  case "nvme": return "bolt.horizontal.circle.fill"
  case "ssd": return "internaldrive.fill"
  case "hdd": return "externaldrive.fill"
  default: return "questionmark.circle.fill"
  }
}

private func worstSeverity(_ devices: [WidgetDeviceSnapshot]) -> Severity {
  devices.map { Severity($0.severity) }.max { $0.rank < $1.rank } ?? .unavailable
}

private func worstDevice(_ devices: [WidgetDeviceSnapshot]) -> WidgetDeviceSnapshot? {
  devices.max { Severity($0.severity).rank < Severity($1.severity).rank }
}

// MARK: - Timeline

struct DriveEntry: TimelineEntry {
  let date: Date
  let devices: [WidgetDeviceSnapshot]
}

private let previewDevices = [
  WidgetDeviceSnapshot(
    id: "preview-1", name: "NVMe SSD", valueText: "47°C", fraction: 0.5,
    severity: "normal", type: "nvme", healthStatus: "OK", lifePercent: 96,
    freeCapacityText: "412 GB free"
  ),
  WidgetDeviceSnapshot(
    id: "preview-2", name: "External HDD", valueText: "61°C", fraction: 0.85,
    severity: "critical", type: "hdd", healthStatus: "OK", lifePercent: 71,
    freeCapacityText: "1.2 TB free"
  ),
  WidgetDeviceSnapshot(
    id: "preview-3", name: "Backup SSD", valueText: "54°C", fraction: 0.65,
    severity: "warning", type: "ssd", healthStatus: "OK", lifePercent: 88,
    freeCapacityText: "89 GB free"
  ),
]

struct DriveProvider: TimelineProvider {
  func placeholder(in context: Context) -> DriveEntry {
    DriveEntry(date: Date(), devices: previewDevices)
  }

  func getSnapshot(in context: Context, completion: @escaping (DriveEntry) -> Void) {
    if context.isPreview {
      completion(DriveEntry(date: Date(), devices: previewDevices))
      return
    }
    completion(DriveEntry(date: Date(), devices: loadSnapshot()?.devices ?? []))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DriveEntry>) -> Void) {
    let entry = DriveEntry(date: Date(), devices: loadSnapshot()?.devices ?? [])
    // The app pushes a fresh snapshot + WidgetCenter.reloadAllTimelines()
    // on every change, so this fallback refresh just guards against the
    // app being closed for a while (e.g. it crashed) - refresh hourly.
    let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }
}

// MARK: - Shared pieces

/// A small colored capsule: icon + label, tinted by severity. Used both as
/// the widget-level summary (header) and per-row when a drive isn't normal.
private struct SeverityBadge: View {
  let severity: Severity
  var compact: Bool = false

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: severity.icon)
        .font(.system(size: compact ? 8 : 9, weight: .bold))
      Text(severity.label)
        .font(.system(size: compact ? 9 : 10, weight: .semibold))
    }
    .foregroundStyle(severity.color)
    .padding(.horizontal, compact ? 5 : 6)
    .padding(.vertical, compact ? 2 : 3)
    .background(severity.color.opacity(0.15), in: Capsule())
  }
}

private struct EmptyStateView: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "externaldrive.badge.questionmark")
        .font(.system(size: 20))
        .foregroundStyle(.secondary)
      Text("No drives yet")
        .font(.system(size: 12, weight: .medium))
      Text("Open DriveGuard to start monitoring")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(14)
  }
}

// MARK: - Small: single-device focus (worst severity wins)

private struct SmallDriveView: View {
  let devices: [WidgetDeviceSnapshot]

  var body: some View {
    if let device = worstDevice(devices) {
      let severity = Severity(device.severity)
      HStack(spacing: 0) {
        Rectangle()
          .fill(severity.color)
          .frame(width: 3)

        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 4) {
            Image(systemName: deviceIcon(device.type))
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)
            Text("DriveGuard")
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if devices.count > 1 {
              Text("+\(devices.count - 1)")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 0)

          Text(device.valueText)
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(severity.color)
            .minimumScaleFactor(0.55)
            .lineLimit(1)

          Text(device.name)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: 0)

          SeverityBadge(severity: severity, compact: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    } else {
      EmptyStateView()
    }
  }
}

// MARK: - Medium/Large: device list

private struct DeviceRow: View {
  let device: WidgetDeviceSnapshot

  private var severity: Severity { Severity(device.severity) }

  var body: some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(severity.color)
        .frame(width: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))

      ZStack {
        Circle()
          .fill(severity.color.opacity(0.15))
          .frame(width: 28, height: 28)
        Image(systemName: deviceIcon(device.type))
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(severity.color)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(device.name)
          .font(.system(size: 12.5, weight: .semibold))
          .lineLimit(1)
        Text(detailLine)
          .font(.system(size: 10, weight: .regular))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 3) {
        Text(device.valueText)
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(severity.color)
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize()
        if severity == .warning || severity == .critical {
          SeverityBadge(severity: severity, compact: true)
        }
      }
    }
    .padding(.vertical, 2)
  }

  private var detailLine: String {
    var parts: [String] = []
    if let health = device.healthStatus, health != "UNKNOWN" { parts.append(health.capitalized) }
    if let life = device.lifePercent { parts.append("\(life)% life") }
    if let free = device.freeCapacityText { parts.append(free) }
    return parts.isEmpty ? "—" : parts.joined(separator: " · ")
  }
}

private struct HeaderRow: View {
  let devices: [WidgetDeviceSnapshot]

  var body: some View {
    HStack {
      HStack(spacing: 5) {
        Image(systemName: "shield.checkerboard")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
        Text("DriveGuard")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      Spacer()
      SeverityBadge(severity: worstSeverity(devices))
    }
  }
}

private struct DeviceListView: View {
  let devices: [WidgetDeviceSnapshot]
  let maxRows: Int

  var body: some View {
    if devices.isEmpty {
      EmptyStateView()
    } else {
      VStack(alignment: .leading, spacing: 0) {
        HeaderRow(devices: devices)
          .padding(.bottom, 10)

        VStack(spacing: 9) {
          ForEach(Array(devices.prefix(maxRows).enumerated()), id: \.element.id) { index, device in
            if index > 0 {
              Divider().opacity(0.4)
            }
            DeviceRow(device: device)
          }
        }

        if devices.count > maxRows {
          Text("+\(devices.count - maxRows) more drive\(devices.count - maxRows == 1 ? "" : "s")")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

// MARK: - Widget entry view

struct DriveGuardWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: DriveProvider.Entry

  var body: some View {
    Group {
      switch family {
      case .systemSmall:
        SmallDriveView(devices: entry.devices)
      case .systemLarge:
        DeviceListView(devices: entry.devices, maxRows: 6)
      default:
        DeviceListView(devices: entry.devices, maxRows: 3)
      }
    }
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
    .description("Live drive temperature, health and warnings at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

#Preview(as: .systemSmall) {
  DriveGuardWidget()
} timeline: {
  DriveEntry(date: .now, devices: previewDevices)
}

#Preview(as: .systemMedium) {
  DriveGuardWidget()
} timeline: {
  DriveEntry(date: .now, devices: previewDevices)
}
