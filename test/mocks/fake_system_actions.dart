import 'package:driveguard/application/protection/system_actions.dart';
import 'package:driveguard/application/protection/thermal_models.dart';

/// Records what the protection engines ask the OS to do; touches nothing.
class FakeActions implements SystemActions {
  int shutdowns = 0;
  int elevatedShutdowns = 0;
  bool shutdownOk = true;
  final killed = <int>[];
  final alive = <int>{};
  List<ProcessSample> procs = const [];
  MemorySnapshot? memory;
  @override
  String? get currentUser => 'me';
  @override
  int get ownPid => 4242;
  @override
  bool get canElevate => true;
  @override
  Future<List<ProcessSample>> topProcesses({
    int limit = 5,
    ProcessSort sort = ProcessSort.cpu,
    bool measureWrites = false,
  }) async => procs;
  @override
  Future<MemorySnapshot?> memorySnapshot() async => memory;
  @override
  Future<bool> isProcessAlive(int pid) async => alive.contains(pid);
  @override
  Future<String?> processName(int pid) async {
    for (final p in procs) {
      if (p.pid == pid) return p.name;
    }
    return null;
  }

  @override
  Future<bool> shutdown({bool elevated = false}) async {
    if (elevated) {
      elevatedShutdowns++;
    } else {
      shutdowns++;
    }
    return shutdownOk;
  }

  @override
  Future<bool> terminateProcess(
    int pid, {
    bool force = false,
    bool elevated = false,
  }) async {
    killed.add(pid);
    alive.remove(pid);
    return true;
  }
}
