// DriveGuard top-panel widget for GNOME Shell (45+, ESM extension format).
//
// This never talks to the running app directly - it watches the snapshot
// file DriveGuard writes on every device/activity change (see
// lib/infrastructure/native/native_widget_bridge.dart) via a Gio file
// monitor, so it keeps showing the last known values even if DriveGuard
// isn't running, and enabling/disabling this extension has zero effect on
// the app or vice versa.
//
// Install: symlink (or copy) this directory into
// ~/.local/share/gnome-shell/extensions/, then
//   gnome-extensions enable driveguard-widget@intersmart.in
// (a Shell restart - Alt+F2, r, Enter on X11, or log out/in on Wayland -
// may be needed the first time). See ../../NATIVE_WIDGETS.md.

import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Must match the directory NativeWidgetBridge writes to: path_provider's
// getApplicationSupportDirectory() (~/.local/share/<APPLICATION_ID from
// linux/CMakeLists.txt>) plus the "driveguard" subfolder AppDatabase/
// NativeWidgetBridge both join onto it.
const SNAPSHOT_PATH = GLib.build_filenamev([
  GLib.get_home_dir(),
  '.local', 'share', 'com.example.driveguard', 'driveguard',
  'widget_snapshot.json',
]);

const SEVERITY_COLOR = {
  critical: '#ff5c5c',
  warning: '#ffb648',
  normal: '#5cd65c',
};

const Indicator = GObject.registerClass(
class Indicator extends PanelMenu.Button {
  _init() {
    super._init(0.0, 'DriveGuard');

    this._label = new St.Label({
      text: '—',
      y_align: Clutter.ActorAlign.CENTER,
    });
    this.add_child(this._label);

    const placeholder = new PopupMenu.PopupMenuItem('No data yet', {reactive: false});
    this.menu.addMenuItem(placeholder);

    this._startWatching();
    this._reload();
  }

  _startWatching() {
    const file = Gio.File.new_for_path(SNAPSHOT_PATH);
    try {
      this._monitor = file.monitor(Gio.FileMonitorFlags.NONE, null);
      this._monitorId = this._monitor.connect('changed', () => this._reload());
    } catch (e) {
      logError(e, 'DriveGuard widget: could not watch snapshot file');
    }
    // The directory (or file) may not exist yet if DriveGuard has never
    // run - fall back to a slow poll so the widget picks it up once it
    // does, without needing the extension re-enabled.
    this._pollId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
      this._reload();
      return GLib.SOURCE_CONTINUE;
    });
  }

  _reload() {
    const file = Gio.File.new_for_path(SNAPSHOT_PATH);
    file.load_contents_async(null, (source, result) => {
      let contents;
      try {
        [, contents] = source.load_contents_finish(result);
      } catch (e) {
        return; // Not written yet - keep showing the last known state.
      }
      let payload;
      try {
        payload = JSON.parse(new TextDecoder().decode(contents));
      } catch (e) {
        logError(e, 'DriveGuard widget: malformed snapshot JSON');
        return;
      }
      this._render(payload.devices ?? []);
    });
  }

  _render(devices) {
    this.menu.removeAll();

    if (devices.length === 0) {
      this._label.text = 'No drives';
      this._label.set_style('');
      this.menu.addMenuItem(new PopupMenu.PopupMenuItem('No drives detected', {reactive: false}));
      return;
    }

    let worst = 'normal';
    for (const device of devices) {
      if (device.severity === 'critical') worst = 'critical';
      else if (device.severity === 'warning' && worst !== 'critical') worst = 'warning';

      const item = new PopupMenu.PopupMenuItem(`${device.name}    ${device.valueText}`, {reactive: false});
      item.label.set_style(`color: ${SEVERITY_COLOR[device.severity] ?? SEVERITY_COLOR.normal};`);
      this.menu.addMenuItem(item);
    }

    const worstDevice = devices.find(d => d.severity === worst) ?? devices[0];
    this._label.text = worst === 'normal' ? worstDevice.valueText : `${worstDevice.valueText} ⚠`;
    this._label.set_style(worst === 'normal' ? '' : `color: ${SEVERITY_COLOR[worst]};`);
  }

  destroy() {
    if (this._monitor) {
      if (this._monitorId) this._monitor.disconnect(this._monitorId);
      this._monitor.cancel();
      this._monitor = null;
    }
    if (this._pollId) {
      GLib.source_remove(this._pollId);
      this._pollId = null;
    }
    super.destroy();
  }
});

export default class DriveGuardWidgetExtension extends Extension {
  enable() {
    this._indicator = new Indicator();
    Main.panel.addToStatusArea(this.uuid, this._indicator);
  }

  disable() {
    this._indicator?.destroy();
    this._indicator = null;
  }
}
