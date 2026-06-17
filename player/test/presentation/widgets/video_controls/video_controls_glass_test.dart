// U5 — glass video controls (plan R4, R10).
//
// The bottom control chrome is a token-driven real-blur glass bar
// ([VideoControlsGlassBar]) instead of the prior black gradient scrim. This
// verifies it renders a BackdropFilter at the chrome blur sigma, that its fill
// clears the R10 legibility floor (so controls stay readable over bright video
// frames), and that arbitrary control children remain hit-testable inside it.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/theme/colors.dart';
import 'package:player/core/theme/depth_tokens.dart';
import 'package:player/presentation/widgets/video_controls/custom_video_controls.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            // Stand-in for the playing video the glass bar samples.
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            Align(alignment: Alignment.bottomCenter, child: child),
          ],
        ),
      ),
    );

void main() {
  group('VideoControlsGlassBar (R4/R10)', () {
    testWidgets('renders token glass (BackdropFilter at the chrome sigma) '
        'instead of a gradient scrim', (tester) async {
      await tester.pumpWidget(
        _host(const VideoControlsGlassBar(child: SizedBox(width: 200, height: 60))),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      final backdrop =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(
        backdrop.filter,
        ImageFilter.blur(
          sigmaX: DepthTokens.blurChrome,
          sigmaY: DepthTokens.blurChrome,
        ),
      );
    });

    testWidgets('control-bar fill clears the legibility floor (R10)',
        (tester) async {
      await tester.pumpWidget(
        _host(const VideoControlsGlassBar(child: SizedBox(width: 200, height: 60))),
      );

      final decoration = tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.byType(BackdropFilter),
              matching: find.byType(DecoratedBox),
            ),
          )
          .decoration as BoxDecoration;
      final fill = decoration.color!;
      expect(fill.a, greaterThanOrEqualTo(DepthTokens.glassLegibilityFloor));
      expect(fill, AppColors.background.withValues(alpha: DepthTokens.chromeFillOpacity));
    });

    testWidgets('control children remain interactive inside the glass bar',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(
          VideoControlsGlassBar(
            child: ElevatedButton(
              onPressed: () => tapped = true,
              child: const Text('play'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('play'));
      expect(tapped, isTrue);
    });
  });
}
