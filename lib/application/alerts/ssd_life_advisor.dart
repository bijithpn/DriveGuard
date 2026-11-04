import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';

enum AdvisorySeverity { info, warning, critical }

class Advisory {
  const Advisory({
    required this.id,
    required this.severity,
    required this.title,
    required this.body,
  });

  /// Stable key so each condition is announced once, and re-announced only
  /// when it gets worse.
  final String id;
  final AdvisorySeverity severity;
  final String title;
  final String body;
}

/// Turns raw SMART/health/capacity numbers into plain-language advice about
/// SSD longevity. Pure function — no I/O, easy to test.
class SsdLifeAdvisor {
  const SsdLifeAdvisor();

  List<Advisory> evaluate(StorageDevice device, {DeviceHealth? previous}) {
    final isSsd =
        device.type == StorageDeviceType.ssd ||
        device.type == StorageDeviceType.nvme;
    final h = device.health;
    final out = <Advisory>[];
    final name = device.displayName;

    String written() {
      final b = h.totalBytesWritten;
      if (b == null) return '';
      return ' Lifetime data written: '
          '${(b / (1000 * 1000 * 1000 * 1000)).toStringAsFixed(1)} TB.';
    }

    if (isSsd) {
      final wear = h.percentageUsed;
      if (wear != null && wear >= 80) {
        final crit = wear >= 90;
        out.add(
          Advisory(
            id: crit ? 'wear-90' : 'wear-80',
            severity: crit
                ? AdvisorySeverity.critical
                : AdvisorySeverity.warning,
            title: crit
                ? '$name is nearly worn out'
                : '$name has used most of its rated life',
            body:
                '$wear% of the rated write endurance is used.${written()} '
                '${crit ? 'Back up important data now and plan a replacement. ' : 'Plan a replacement and keep backups current. '}'
                'Reduce heavy writes (downloads, scratch files, VMs) to slow wear.',
          ),
        );
      }

      final left = h.ssdLifeLeftPercent;
      if (left != null && left <= 20) {
        final crit = left <= 10;
        out.add(
          Advisory(
            id: crit ? 'life-10' : 'life-20',
            severity: crit
                ? AdvisorySeverity.critical
                : AdvisorySeverity.warning,
            title: '$name has $left% of its life left',
            body:
                'The drive reports only $left% life remaining.${written()} '
                'Back up your data and plan a replacement.',
          ),
        );
      }

      final spare = h.availableSparePercent;
      if (spare != null) {
        final threshold = h.availableSpareThreshold ?? 10;
        if (spare <= threshold) {
          out.add(
            Advisory(
              id: 'spare-crit',
              severity: AdvisorySeverity.critical,
              title: '$name is out of spare blocks',
              body:
                  'Available spare is $spare% (threshold $threshold%). The '
                  'drive can no longer replace failing cells safely — back up '
                  'now and replace it.',
            ),
          );
        } else if (spare <= threshold + 10) {
          out.add(
            Advisory(
              id: 'spare-warn',
              severity: AdvisorySeverity.warning,
              title: '$name spare capacity is getting low',
              body:
                  'Available spare is $spare% and approaching the failure '
                  'threshold of $threshold%.',
            ),
          );
        }
      }

      final usage = device.capacity.usagePercent;
      if (usage != null && usage >= 80) {
        out.add(
          Advisory(
            id: 'free-space-80',
            severity: AdvisorySeverity.info,
            title: 'Keep some free space to protect $name',
            body:
                '${usage.toStringAsFixed(0)}% of the drive is used. SSDs wear '
                'faster and run hotter when nearly full because they have less '
                'room for wear levelling. Aim to keep 15–20% free — Storage '
                'Sense can find what to remove.',
          ),
        );
      }
    }

    // Unsafe shutdowns (power loss / forced shutdowns) — relevant to every
    // drive type and directly tied to forced-shutdown scenarios.
    final now = h.unsafeShutdowns;
    final before = previous?.unsafeShutdowns;
    if (now != null && before != null && now > before) {
      final n = now - before;
      out.add(
        Advisory(
          id: 'unsafe-$now',
          severity: AdvisorySeverity.warning,
          title: '$name saw $n unsafe shutdown${n == 1 ? '' : 's'}',
          body:
              'The computer lost power or was forced off while the drive was '
              'active ($now in total). Unsafe shutdowns can corrupt data and '
              'stress the SSD — shut down normally, and check the battery/PSU '
              'and cooling if this was unexpected.',
        ),
      );
    }
    return out;
  }
}
