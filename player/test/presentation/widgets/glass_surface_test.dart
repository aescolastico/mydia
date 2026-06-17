import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/theme/colors.dart';
import 'package:player/presentation/widgets/glass_surface.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

BackdropFilter _backdropOf(WidgetTester tester) {
  return tester.widget<BackdropFilter>(find.byType(BackdropFilter));
}

/// Extracts the blur sigma from a [BackdropFilter]'s image filter by matching
/// against a freshly built blur filter (ImageFilter equality is value-based).
bool _hasBlurSigma(BackdropFilter f, double sigma) {
  return f.filter == ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}

DecoratedBox _decoratedBoxOf(WidgetTester tester) {
  return tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(BackdropFilter),
      matching: find.byType(DecoratedBox),
    ),
  );
}

void main() {
  group('GlassSurface.appBar', () {
    testWidgets('renders a BackdropFilter with sigma 10 and the fill opacity',
        (tester) async {
      await tester.pumpWidget(
        _host(GlassSurface.appBar(child: const SizedBox(width: 50, height: 50))),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(_hasBlurSigma(_backdropOf(tester), 10), isTrue);

      final decoration =
          _decoratedBoxOf(tester).decoration as BoxDecoration;
      expect(
        decoration.color,
        AppColors.background.withValues(alpha: 0.8),
      );
    });

    testWidgets('honors an explicit opacity override (0.85)', (tester) async {
      await tester.pumpWidget(
        _host(GlassSurface.appBar(opacity: 0.85, child: const SizedBox())),
      );
      final decoration =
          _decoratedBoxOf(tester).decoration as BoxDecoration;
      expect(
        decoration.color,
        AppColors.background.withValues(alpha: 0.85),
      );
    });
  });

  group('GlassSurface.modal', () {
    testWidgets('renders border + radius 20 + sigma 8 fill at 0.6',
        (tester) async {
      await tester.pumpWidget(
        _host(GlassSurface.modal(child: const SizedBox())),
      );

      expect(_hasBlurSigma(_backdropOf(tester), 8), isTrue);

      final decoration =
          _decoratedBoxOf(tester).decoration as BoxDecoration;
      expect(decoration.color, AppColors.surface.withValues(alpha: 0.6));
      expect(decoration.border, isNotNull);
      expect(decoration.borderRadius, BorderRadius.circular(20));
    });
  });

  group('GlassSurface.hoverOverlay', () {
    testWidgets('renders sigma 2 with a dark gradient and radius 12',
        (tester) async {
      await tester.pumpWidget(
        _host(GlassSurface.hoverOverlay(child: const SizedBox())),
      );

      expect(_hasBlurSigma(_backdropOf(tester), 2), isTrue);

      final decoration =
          _decoratedBoxOf(tester).decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
      expect(decoration.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('honors a custom borderRadius', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassSurface.hoverOverlay(
            borderRadius: BorderRadius.circular(8),
            child: const SizedBox(),
          ),
        ),
      );
      final decoration =
          _decoratedBoxOf(tester).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));
    });
  });

  group('grouped rendering', () {
    testWidgets('a BackdropGroup wrapping two grouped surfaces builds and '
        'both render', (tester) async {
      await tester.pumpWidget(
        _host(
          BackdropGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSurface.appBar(
                  grouped: true,
                  child: const Text('one'),
                ),
                GlassSurface.modal(
                  grouped: true,
                  child: const Text('two'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(BackdropGroup), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
    });
  });

  group('child rendering', () {
    testWidgets('renders its child in every preset', (tester) async {
      for (final surface in [
        GlassSurface.appBar(child: const Text('appbar')),
        GlassSurface.modal(child: const Text('modal')),
        GlassSurface.hoverOverlay(child: const Text('hover')),
      ]) {
        await tester.pumpWidget(_host(surface));
        await tester.pump();
      }
      // Last pump is the hover overlay preset.
      expect(find.text('hover'), findsOneWidget);
    });

    testWidgets('wraps the blur region in a RepaintBoundary', (tester) async {
      await tester.pumpWidget(
        _host(GlassSurface.appBar(child: const SizedBox())),
      );
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });
}
