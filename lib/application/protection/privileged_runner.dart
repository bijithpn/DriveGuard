/// Runs a single command with administrator/root rights after the OS shows
/// its own authentication prompt (macOS password dialog, Linux polkit, Windows
/// UAC). DriveGuard never stores credentials and never elevates silently —
/// every call here must follow an explicit user action.
abstract class PrivilegedRunner {
  /// True when an elevation mechanism exists on this machine.
  Future<bool> get isAvailable;

  /// Runs [executable] with [args]. Returns true when the command ran and
  /// exited with status 0; false if the user declined or it failed.
  Future<bool> run(
    String executable,
    List<String> args, {
    required String reason,
  });
}
