import 'thermal_models.dart';

/// OS-level operations the protection engines can perform. Abstract so tests
/// can verify behaviour without ever powering anything off or killing
/// anything.
abstract class SystemActions {
  String? get currentUser;

  /// Pid of DriveGuard itself — never offered for termination.
  int get ownPid;

  /// True when the OS has a usable administrator/root prompt.
  bool get canElevate;

  Future<List<ProcessSample>> topProcesses({
    int limit = 5,
    ProcessSort sort = ProcessSort.cpu,
    bool measureWrites = false,
  });

  Future<MemorySnapshot?> memorySnapshot();

  Future<bool> isProcessAlive(int pid);

  /// Current executable name of [pid], or null if it no longer exists. Used
  /// to make sure a recycled pid is never killed by mistake.
  Future<String?> processName(int pid);

  /// Asks the process to end. [force] kills immediately; [elevated] retries
  /// through the OS admin prompt (user must approve it).
  Future<bool> terminateProcess(
    int pid, {
    bool force = false,
    bool elevated = false,
  });

  /// Requests a system shutdown. With [elevated] it goes through the admin
  /// prompt and forces apps closed.
  Future<bool> shutdown({bool elevated = false});
}
