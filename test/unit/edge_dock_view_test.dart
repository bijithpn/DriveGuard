import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/presentation/widget/edge_dock_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAccent', () {
    test('auto resolves to null (caller falls back to severity color)', () {
      expect(resolveAccent(EdgeDockAccent.auto), isNull);
    });

    test('every non-auto accent resolves to a distinct color', () {
      final nonAuto = EdgeDockAccent.values.where(
        (a) => a != EdgeDockAccent.auto,
      );
      final colors = nonAuto.map(resolveAccent).toList();
      expect(colors, everyElement(isNotNull));
      expect(colors.toSet().length, colors.length);
    });
  });
}
