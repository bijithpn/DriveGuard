import 'dart:async';
import 'dart:io';

import '../constants/app_constants.dart';
import '../errors/storage_exceptions.dart';
import '../logging/app_logger.dart';

class ProcessResult2 {
  const ProcessResult2(this.stdout, this.stderr, this.exitCode);
  final String stdout;
  final String stderr;
  final int exitCode;
}

class SafeProcessRunner {
  SafeProcessRunner._();
  static final SafeProcessRunner instance = SafeProcessRunner._();

  final Map<String, bool> _existenceCache = {};

  Future<bool> exists(
    String executable, {
    List<String> extraPaths = const [],
  }) async {
    if (_existenceCache.containsKey(executable)) {
      return _existenceCache[executable]!;
    }
    final found = await _locate(executable, extraPaths) != null;
    _existenceCache[executable] = found;
    return found;
  }

  Future<String?> _locate(String executable, List<String> extraPaths) async {
    if (Platform.isWindows && !executable.toLowerCase().endsWith('.exe')) {
      executable = '$executable.exe';
    }
    if (executable.contains(Platform.pathSeparator)) {
      return File(executable).existsSync() ? executable : null;
    }
    final pathEnv = Platform.environment['PATH'] ?? '';
    final dirs = [
      ...pathEnv.split(Platform.isWindows ? ';' : ':'),
      ...extraPaths,
    ];
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      final candidate = '$dir${Platform.pathSeparator}$executable';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<ProcessResult2> run(
    String executable,
    List<String> args, {
    Duration timeout = AppConstants.externalCommandTimeout,
    bool requireZeroExit = true,
    List<String> extraPaths = const [],
  }) async {
    final resolved = await _locate(executable, extraPaths);
    if (resolved == null) {
      throw CommandExecutionException('Executable not found: $executable');
    }

    late Process process;
    try {
      process = await Process.start(resolved, args, runInShell: false);
    } catch (e) {
      throw CommandExecutionException('Failed to start $executable: $e');
    }

    final stdoutFuture = process.stdout
        .transform(const _Utf8LenientDecoder())
        .join();
    final stderrFuture = process.stderr
        .transform(const _Utf8LenientDecoder())
        .join();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw CommandExecutionException(
            'Command timed out after ${timeout.inSeconds}s: $executable',
          );
        },
      );
    } on TimeoutException {
      process.kill();
      throw CommandExecutionException(
        'Command timed out after ${timeout.inSeconds}s: $executable',
      );
    }

    final stdoutStr = await stdoutFuture;
    final stderrStr = await stderrFuture;

    if (requireZeroExit && exitCode != 0) {
      AppLogger.instance.warning(
        'SafeProcessRunner',
        '$executable exited with $exitCode: ${stderrStr.trim()}',
      );
      throw CommandExecutionException(
        '$executable exited with code $exitCode: ${stderrStr.trim()}',
      );
    }
    return ProcessResult2(stdoutStr, stderrStr, exitCode);
  }
}

class _Utf8LenientDecoder extends StreamTransformerBase<List<int>, String> {
  const _Utf8LenientDecoder();
  @override
  Stream<String> bind(Stream<List<int>> stream) {
    return stream.map((bytes) => String.fromCharCodes(bytes));
  }
}
