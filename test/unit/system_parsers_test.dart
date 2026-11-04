import 'package:driveguard/infrastructure/system/os_privileged_runner.dart';
import 'package:driveguard/infrastructure/system/system_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ps (macOS / Linux)', () {
    const out = '''
    1 root 0.0 1024 /sbin/launchd
  123 me 12.5 204800 /Applications/Foo.app/Contents/MacOS/Foo
  456 me 88.0 2097152 /usr/bin/ffmpeg
  789 me 99.0 2048 /bin/ps
  garbage line
''';
    test('parses cpu, rss (KB→bytes), user and basename; skips ps/self', () {
      final p = parsePsOutput(out, selfPid: 1);
      expect(p.map((e) => e.name), ['Foo', 'ffmpeg']);
      final ff = p.last;
      expect(ff.pid, 456);
      expect(ff.user, 'me');
      expect(ff.cpuPercent, 88.0);
      expect(ff.rssBytes, 2097152 * 1024);
    });

    test('handles locales that print a decimal comma', () {
      final p = parsePsOutput('  10 me 7,5 100 /bin/x');
      expect(p.single.cpuPercent, 7.5);
    });
  });

  group('Windows process CSV', () {
    const csv = '''
"IDProcess","PercentProcessorTime","WorkingSet","IOWriteBytesPersec","Name"
"4412","35","1073741824","73400320","chrome#3"
"88","2","1000","0","svchost"
"0","99","0","0","Idle"
''';
    test('maps columns by header, strips #N, keeps measured write rate', () {
      final p = parseWindowsProcessCsv(csv);
      expect(p, hasLength(2));
      expect(p.first.name, 'chrome.exe');
      expect(p.first.rssBytes, 1073741824);
      expect(p.first.writeBytesPerSecond, 73400320);
    });
    test('returns nothing for unexpected output', () {
      expect(parseWindowsProcessCsv('nonsense'), isEmpty);
      expect(parseWindowsProcessCsv(''), isEmpty);
    });
  });

  group('memory', () {
    test('Linux /proc/meminfo', () {
      const t = '''
MemTotal:       16000000 kB
MemFree:          500000 kB
MemAvailable:    1600000 kB
SwapTotal:       4000000 kB
SwapFree:        1000000 kB
''';
      final m = parseMeminfo(t)!;
      expect(m.totalBytes, 16000000 * 1024);
      expect(m.availablePercent, closeTo(10, 0.01));
      expect(m.swapUsedBytes, 3000000 * 1024);
    });

    test('Linux without MemAvailable falls back to free+cache+buffers', () {
      final m = parseMeminfo(
        'MemTotal: 1000 kB\nMemFree: 100 kB\nCached: 200 kB\nBuffers: 50 kB\n',
      )!;
      expect(m.availableBytes, 350 * 1024);
    });

    test('macOS vm_stat + sysctl', () {
      const vm = '''
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               1000.
Pages active:                           212563.
Pages inactive:                           3000.
Pages speculative:                        1000.
''';
      final m = parseMacMemory(
        vmStat: vm,
        memsize: '17179869184\n',
        swapUsage:
            'total = 2048.00M  used = 1536.50M  free = 511.50M  (encrypted)',
      )!;
      expect(m.totalBytes, 17179869184);
      expect(m.availableBytes, 5000 * 16384);
      expect(m.swapUsedBytes, (1536.5 * 1024 * 1024).round());
    });

    test('Windows uses Available (incl. standby cache) and page file', () {
      const json = '''
{"TotalVisibleMemorySize":16000000,"FreePhysicalMemory":300000,
 "AvailableBytes":8589934592,"PageFileUsedMB":1500,"PageFileTotalMB":4096}''';
      final m = parseWindowsMemory(json)!;
      // FreePhysicalMemory alone would say ~2% (false alarm); Available says ~52%.
      expect(m.availablePercent, greaterThan(50));
      expect(m.swapUsedBytes, 1500 * 1024 * 1024);
      expect(parseWindowsMemory('not json'), isNull);
    });

    test('/proc/<pid>/io write_bytes', () {
      expect(
        parseProcIoWriteBytes('rchar: 1\nwchar: 2\nwrite_bytes: 4096\n'),
        4096,
      );
      expect(parseProcIoWriteBytes('nope'), isNull);
    });
  });

  group('elevation command builders', () {
    test('macOS script quotes every argument and escapes AppleScript', () {
      final s = OsPrivilegedRunner.buildMacScript('/bin/sh', [
        '-c',
        "echo 'hi'; rm -rf -- \"/tmp/a b\"",
      ], 'Needs "admin"');
      expect(s, startsWith('do shell script "'));
      expect(s, contains('with administrator privileges'));
      // single quote inside the shell arg is closed/escaped/reopened
      expect(s, contains(r"'\\''"));
      // double quotes are backslash-escaped for AppleScript
      expect(s, contains(r'\"'));
      expect(s, contains('prompt "Needs \\"admin\\""'));
    });

    test('Windows script uses RunAs and an array of quoted args', () {
      final s = OsPrivilegedRunner.buildWindowsScript('taskkill', [
        '/PID',
        '123',
        '/F',
      ]);
      expect(s, contains("-FilePath 'taskkill'"));
      expect(s, contains("-ArgumentList '/PID','123','/F'"));
      expect(s, contains('-Verb RunAs'));
      expect(s, contains(r'exit $p.ExitCode'));
    });

    test('PowerShell encoding is UTF-16LE base64', () {
      // "A" → 0x41 0x00 → "QQA="
      expect(OsPrivilegedRunner.encodePowerShell('A'), 'QQA=');
    });
  });
}
