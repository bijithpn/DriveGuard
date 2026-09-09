/// Shared ATA/SATA SMART attribute extraction, used by every platform's
/// storage monitor. See docs/superpowers/specs/2026-09-09-smart-attributes-design.md.
class AtaSmartExtras {
  const AtaSmartExtras({
    this.reallocatedSectorCount,
    this.reallocatedEventCount,
    this.currentPendingSectorCount,
    this.offlineUncorrectableCount,
    this.ssdLifeLeftPercent,
  });

  static const empty = AtaSmartExtras();

  final int? reallocatedSectorCount;
  final int? reallocatedEventCount;
  final int? currentPendingSectorCount;
  final int? offlineUncorrectableCount;
  final int? ssdLifeLeftPercent;

  static const _reallocatedSectorIds = [5];
  static const _reallocatedEventIds = [196];
  static const _pendingSectorIds = [197];
  static const _offlineUncorrectableIds = [198];
  // Vendor-specific: SSDs report remaining life/wear under different ids
  // depending on manufacturer. Matched by id first, then by name as a
  // fallback for vendors smartctl doesn't have a normalized id table for.
  static const _lifeLeftIds = [231, 202, 173, 177];
  static const _lifeLeftNameHints = ['life_left', 'lifetime_remain', 'wear'];

  /// Parses smartctl's `-j`/`--json` output (the `ata_smart_attributes.table`
  /// array). Returns [empty] if the key is missing or malformed — this
  /// device may be NVMe-only, or smartctl may not support it.
  factory AtaSmartExtras.fromSmartctlJson(Map<String, dynamic> json) {
    try {
      final table =
          (json['ata_smart_attributes'] as Map<String, dynamic>?)?['table'];
      if (table is! List) return empty;
      final entries = table.whereType<Map<String, dynamic>>().toList();

      return AtaSmartExtras(
        reallocatedSectorCount: _rawValueForIds(entries, _reallocatedSectorIds),
        reallocatedEventCount: _rawValueForIds(entries, _reallocatedEventIds),
        currentPendingSectorCount: _rawValueForIds(entries, _pendingSectorIds),
        offlineUncorrectableCount: _rawValueForIds(
          entries,
          _offlineUncorrectableIds,
        ),
        ssdLifeLeftPercent: _lifeLeftPercent(entries),
      );
    } catch (_) {
      return empty;
    }
  }

  static int? _rawValueForIds(List<Map<String, dynamic>> table, List<int> ids) {
    for (final entry in table) {
      final id = (entry['id'] as num?)?.toInt();
      if (id == null || !ids.contains(id)) continue;
      final raw = entry['raw'];
      if (raw is Map<String, dynamic>) {
        final value = raw['value'];
        if (value is num) return value.toInt();
      }
    }
    return null;
  }

  static int? _lifeLeftPercent(List<Map<String, dynamic>> table) {
    for (final entry in table) {
      final id = (entry['id'] as num?)?.toInt();
      final name = (entry['name'] as String?)?.toLowerCase() ?? '';
      final matchesId = id != null && _lifeLeftIds.contains(id);
      final matchesName = _lifeLeftNameHints.any(name.contains);
      if (!matchesId && !matchesName) continue;
      // The normalized attribute value is the conventional stand-in for
      // "percent life remaining" for these vendor-specific wear attributes.
      final normalized = (entry['value'] as num?)?.toInt();
      if (normalized != null && normalized >= 0 && normalized <= 100) {
        return normalized;
      }
    }
    return null;
  }

  /// Parses the raw ATA SMART attribute table as returned by Windows'
  /// `MSStorageDriver_FailurePredictData.VendorSpecific` (root\wmi). Layout:
  /// 2-byte header, then up to 30 fixed 12-byte records:
  /// `[id(1), statusFlags(2 LE), current(1), worst(1), raw(6 LE), reserved(1)]`.
  /// A record with id 0 marks the end of valid entries. Pure/offline parsing
  /// — the only part of the Windows SMART path testable without a Windows
  /// machine.
  factory AtaSmartExtras.fromRawAttributeBlock(List<int> bytes) {
    try {
      if (bytes.length < 2) return empty;
      int? reallocatedSectors;
      int? reallocatedEvents;
      int? pendingSectors;
      int? offlineUncorrectable;
      int? lifeLeft;

      var offset = 2;
      while (offset + 12 <= bytes.length) {
        final id = bytes[offset];
        if (id == 0) break;
        final current = bytes[offset + 3];
        // Raw value: 6 bytes, little-endian. Most attributes only use the
        // low 32 bits in practice; read all 6 to avoid truncating drives
        // that do report larger counts.
        var raw = 0;
        for (var i = 0; i < 6; i++) {
          raw |= bytes[offset + 5 + i] << (8 * i);
        }

        if (_reallocatedSectorIds.contains(id)) reallocatedSectors = raw;
        if (_reallocatedEventIds.contains(id)) reallocatedEvents = raw;
        if (_pendingSectorIds.contains(id)) pendingSectors = raw;
        if (_offlineUncorrectableIds.contains(id)) offlineUncorrectable = raw;
        if (_lifeLeftIds.contains(id) && current >= 0 && current <= 100) {
          lifeLeft = current;
        }

        offset += 12;
      }

      return AtaSmartExtras(
        reallocatedSectorCount: reallocatedSectors,
        reallocatedEventCount: reallocatedEvents,
        currentPendingSectorCount: pendingSectors,
        offlineUncorrectableCount: offlineUncorrectable,
        ssdLifeLeftPercent: lifeLeft,
      );
    } catch (_) {
      return empty;
    }
  }
}
