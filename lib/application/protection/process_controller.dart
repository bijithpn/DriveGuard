import 'dart:async';

import '../../core/logging/app_logger.dart';
import 'system_actions.dart';
import 'thermal_models.dart';

enum KillAccess {
  /// The user's own process — can be quit directly.
  own,

  /// Owned by another account/root; needs the OS admin prompt.
  needsAdmin,

  /// Critical OS component — never offered.
  never,
}

/// Processes that must never be terminated: doing so would log the user out,
/// freeze the desktop, or crash the OS.
const _protectedProcesses = <String>{
  // macOS
  'kernel_task', 'launchd', 'windowserver', 'loginwindow', 'finder', 'dock',
  'systemuiserver',
  'coreaudiod',
  'configd',
  'opendirectoryd',
  'diskarbitrationd',
  'distnoted', 'securityd', 'trustd', 'cfprefsd', 'fseventsd', 'logd',
  // Linux
  'systemd', 'init', 'xorg', 'xwayland', 'gnome-shell', 'kwin_x11',
  'kwin_wayland', 'plasmashell', 'dbus-daemon', 'sshd', 'networkmanager',
  'gdm', 'lightdm', 'sddm', 'udevd', 'systemd-udevd', 'journald',
  // Windows
  'system', 'idle', 'registry', 'smss.exe', 'csrss.exe', 'wininit.exe',
  'winlogon.exe', 'services.exe', 'lsass.exe', 'svchost.exe', 'explorer.exe',
  'dwm.exe', 'fontdrvhost.exe', 'sihost.exe', 'taskhostw.exe',
};

KillAccess killAccess(ProcessSample p, {String? currentUser, int? ownPid}) {
  if (p.pid <= 1 || p.pid == ownPid) return KillAccess.never;
  if (_protectedProcesses.contains(p.name.toLowerCase())) {
    return KillAccess.never;
  }
  if (p.user != null && currentUser != null && p.user != currentUser) {
    return KillAccess.needsAdmin;
  }
  return KillAccess.own;
}

/// Quits processes safely: verifies identity, tries a graceful quit first,
/// reports whether it worked, and only uses force / administrator rights when
/// the caller (an explicit user action) asks for them.
class ProcessController {
  ProcessController(
    this._actions, {
    this.waitForExit = const Duration(seconds: 3),
  });

  static const _tag = 'ProcessController';
  final SystemActions _actions;
  final Duration waitForExit;

  KillAccess accessFor(ProcessSample p) =>
      killAccess(p, currentUser: _actions.currentUser, ownPid: _actions.ownPid);

  Future<QuitResult> quit(
    ProcessSample p, {
    bool force = false,
    bool admin = false,
  }) async {
    final access = accessFor(p);
    if (access == KillAccess.never) return QuitResult.notAllowed;
    if (access == KillAccess.needsAdmin && !admin) return QuitResult.denied;

    // The sample may be minutes old: make sure the pid still belongs to the
    // same program before sending a signal to it.
    final current = await _actions.processName(p.pid);
    if (current == null) return QuitResult.quit; // already gone
    if (current.toLowerCase() != p.name.toLowerCase()) {
      AppLogger.instance.warning(
        _tag,
        'pid ${p.pid} is now "$current", not "${p.name}" — not touching it',
      );
      return QuitResult.notAllowed;
    }

    final sent = await _actions.terminateProcess(
      p.pid,
      force: force,
      elevated: admin,
    );
    if (!sent) return admin ? QuitResult.failed : QuitResult.denied;

    final deadline = DateTime.now().add(waitForExit);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _actions.isProcessAlive(p.pid)) {
        AppLogger.instance.warning(
          _tag,
          'Stopped ${p.name} (${p.pid}) force=$force admin=$admin',
        );
        return QuitResult.quit;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return QuitResult.stillRunning;
  }
}
