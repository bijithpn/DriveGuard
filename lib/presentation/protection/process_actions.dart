import 'package:flutter/material.dart';

import '../../application/protection/thermal_models.dart';
import '../theme/app_theme.dart';

typedef QuitCallback = Future<QuitResult> Function({bool force, bool admin});

/// "Quit `app`" with honest escalation: a normal quit first, then Force quit
/// if it ignores that, then administrator rights (via the OS's own password
/// prompt) if the system refuses. Nothing is forced without a click.
class ProcessQuitButtons extends StatefulWidget {
  const ProcessQuitButtons({
    super.key,
    required this.processName,
    required this.onQuit,
    this.needsAdmin = false,
    this.onFinished,
  });

  final String processName;
  final QuitCallback onQuit;

  /// The process belongs to another account: go straight to the admin path.
  final bool needsAdmin;
  final VoidCallback? onFinished;

  @override
  State<ProcessQuitButtons> createState() => _ProcessQuitButtonsState();
}

enum _Step { quit, force, admin, done }

class _ProcessQuitButtonsState extends State<ProcessQuitButtons> {
  late _Step _step = widget.needsAdmin ? _Step.admin : _Step.quit;
  bool _busy = false;
  String? _note;

  Future<void> _run({bool force = false, bool admin = false}) async {
    if (admin) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Force quit ${widget.processName} as administrator?'),
          content: const Text(
            'Your computer will ask for your administrator password (or '
            'approval). Unsaved work in this app will be lost. DriveGuard '
            'never sees or stores your password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _note = null;
    });
    final r = await widget.onQuit(force: force || admin, admin: admin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (r) {
        case QuitResult.quit:
          _step = _Step.done;
          _note = '${widget.processName} was stopped.';
          widget.onFinished?.call();
        case QuitResult.stillRunning:
          _step = admin ? _Step.admin : _Step.force;
          _note = '${widget.processName} is still running.';
        case QuitResult.denied:
          _step = _Step.admin;
          _note = 'The system needs administrator permission to stop it.';
        case QuitResult.failed:
          _note = 'Could not stop it (permission was not granted).';
        case QuitResult.notAllowed:
          _step = _Step.done;
          _note = 'This is a protected system process and can’t be stopped.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.processName;
    final button = switch (_step) {
      _Step.quit => OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(),
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: Text('Quit $name'),
      ),
      _Step.force => OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(force: true),
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
        icon: const Icon(Icons.flash_on_rounded, size: 18),
        label: Text('Force quit $name'),
      ),
      _Step.admin => OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(admin: true),
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.critical),
        icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
        label: const Text('Force quit as administrator'),
      ),
      _Step.done => null,
    };
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ?button,
        if (_busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ?(_note == null
            ? null
            : Text(_note!, style: const TextStyle(fontSize: 12.5))),
      ],
    );
  }
}
