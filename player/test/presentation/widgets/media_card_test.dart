// U6 — solid elevated posters + hover demotion (plan R7, R11; AE1).
//
// The media card is a solid, always-elevated poster with a resting token shadow
// (depth at rest, R7). Hover is demoted to a small lift with a slight shadow
// deepening — no 1.04 scale jump, no specular sheen, and no per-card live blur
// (R8/R11). Under reduced motion the lift collapses while the resting shadow
// stays.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/theme/depth_tokens.dart';
import 'package:player/presentation/widgets/media_card.dart';
import 'package:player/presentation/widgets/progress_overlay.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// Largest scale factor applied by any [Transform] in the tree. A poster that
/// never scales up keeps this at ~1.0.
double _maxScale(WidgetTester tester) {
  var maxScale = 1.0;
  for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
    final s = t.transform.getMaxScaleOnAxis();
    if (s > maxScale) maxScale = s;
  }
  return maxScale;
}

/// The vertical translation applied by the lift [Transform] (negative = up).
double _liftY(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(find.byType(Transform));
  if (transforms.isEmpty) return 0;
  return transforms.first.transform.getTranslation().y;
}

/// The poster's resting/hover shadow box (the one carrying a boxShadow).
BoxDecoration _shadowDecoration(WidgetTester tester) {
  for (final d in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final deco = d.decoration;
    if (deco is BoxDecoration &&
        deco.boxShadow != null &&
        deco.boxShadow!.isNotEmpty) {
      return deco;
    }
  }
  fail('no DecoratedBox with a boxShadow found');
}

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(target));
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
  group('MediaCard solid poster (R7)', () {
    testWidgets('has a visible resting shadow with no hover', (tester) async {
      await tester.pumpWidget(_host(const MediaCard(title: 'Movie')));

      final deco = _shadowDecoration(tester);
      expect(deco.boxShadow!.first.color.a, greaterThan(0));
      // At rest the shadow is the resting token, not the hover token.
      expect(deco.boxShadow, DepthTokens.posterResting);
    });

    testWidgets('renders no live blur in its subtree (R8)', (tester) async {
      await tester.pumpWidget(_host(const MediaCard(title: 'Movie')));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('renders the progress overlay when progress is set',
        (tester) async {
      await tester.pumpWidget(
        _host(const MediaCard(title: 'Movie', progressPercentage: 42)),
      );
      expect(find.byType(ProgressOverlay), findsOneWidget);
    });
  });

  group('MediaCard hover demotion (R11)', () {
    testWidgets('hover lifts slightly with no scale jump or live blur',
        (tester) async {
      await tester.pumpWidget(_host(const MediaCard(title: 'Movie')));

      await _hover(tester, find.byType(MediaCard));

      // A gentle upward lift...
      expect(_liftY(tester), lessThan(0));
      // ...but never a scale jump (the prior 1.04 treatment is gone).
      expect(_maxScale(tester), lessThanOrEqualTo(1.001));
      // ...and still no per-card BackdropFilter (faux overlay).
      expect(find.byType(BackdropFilter), findsNothing);
      // The shadow deepens to the hover token.
      expect(_shadowDecoration(tester).boxShadow, DepthTokens.posterHover);
    });

    testWidgets('under reduced motion the lift collapses but resting shadow '
        'stays (AE1)', (tester) async {
      await tester.pumpWidget(
        _host(const MediaCard(title: 'Movie'), reduceMotion: true),
      );

      await _hover(tester, find.byType(MediaCard));

      expect(_liftY(tester), 0);
      expect(_maxScale(tester), lessThanOrEqualTo(1.001));
      expect(_shadowDecoration(tester).boxShadow, DepthTokens.posterResting);
    });

    testWidgets('tap still fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(MediaCard(title: 'Movie', onTap: () => tapped = true)),
      );
      // Tap within the poster body (the Column expands to max height, so its
      // geometric center sits below the poster in empty space).
      final topLeft = tester.getTopLeft(find.byType(MediaCard));
      await tester.tapAt(topLeft + const Offset(65, 95));
      expect(tapped, isTrue);
    });
  });
}
