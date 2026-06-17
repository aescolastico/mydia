import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/presentation/widgets/specular_sheen.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: 200, height: 300, child: child),
        ),
      ),
    ),
  );
}

/// A child that counts how many times it builds, to prove the sheen does not
/// rebuild the wrapped subtree on hover.
class _BuildCounter extends StatelessWidget {
  final List<int> builds;
  const _BuildCounter(this.builds);

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const ColoredBox(color: Colors.black);
  }
}

void main() {
  group('SpecularSheen.alignmentFor', () {
    test('maps the center of the box to Alignment.center', () {
      expect(
        SpecularSheen.alignmentFor(const Offset(100, 150), const Size(200, 300)),
        const Alignment(0, 0),
      );
    });

    test('maps the top-left corner to (-1, -1)', () {
      expect(
        SpecularSheen.alignmentFor(Offset.zero, const Size(200, 300)),
        const Alignment(-1, -1),
      );
    });

    test('maps the bottom-right corner to (1, 1)', () {
      expect(
        SpecularSheen.alignmentFor(const Offset(200, 300), const Size(200, 300)),
        const Alignment(1, 1),
      );
    });

    test('clamps out-of-bounds positions to the edge', () {
      expect(
        SpecularSheen.alignmentFor(const Offset(400, -50), const Size(200, 300)),
        const Alignment(1, -1),
      );
    });

    test('degenerate size returns center', () {
      expect(
        SpecularSheen.alignmentFor(const Offset(10, 10), Size.zero),
        Alignment.center,
      );
    });
  });

  group('SpecularSheen widget', () {
    testWidgets('hovering shows a sheen without rebuilding the child',
        (tester) async {
      final builds = <int>[];
      await tester.pumpWidget(_host(SpecularSheen(child: _BuildCounter(builds))));
      await tester.pump();

      final buildsAfterMount = builds.length;

      // No sheen until the cursor enters.
      expect(_sheenGradient(tester), isNull);

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SpecularSheen)));
      await tester.pump();

      // Sheen gradient now present.
      expect(_sheenGradient(tester), isNotNull);
      // The wrapped child did not rebuild on hover.
      expect(builds.length, buildsAfterMount);
    });

    testWidgets('pointer exit clears the sheen', (tester) async {
      await tester.pumpWidget(_host(const SpecularSheen(child: SizedBox())));
      await tester.pump();

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SpecularSheen)));
      await tester.pump();
      expect(_sheenGradient(tester), isNotNull);

      // Move far away -> exit.
      await gesture.moveTo(const Offset(-500, -500));
      await tester.pump();
      expect(_sheenGradient(tester), isNull);
    });

    testWidgets('reduced motion renders no sheen and ignores hover',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const SpecularSheen(child: SizedBox()),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // No MouseRegion sheen wrapper is attached at all.
      expect(find.byType(ValueListenableBuilder<Offset?>), findsNothing);

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SpecularSheen)));
      await tester.pump();

      expect(_sheenGradient(tester), isNull);
    });
  });
}

/// Finds the radial sheen gradient if one is currently painted.
RadialGradient? _sheenGradient(WidgetTester tester) {
  final decorated = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .where((d) => d.decoration is BoxDecoration)
      .map((d) => (d.decoration as BoxDecoration).gradient)
      .whereType<RadialGradient>();
  return decorated.isEmpty ? null : decorated.first;
}
