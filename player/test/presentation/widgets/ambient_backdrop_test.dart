import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/presentation/widgets/ambient_backdrop.dart';

import '../../test_utils/mock_network_images.dart';

Widget _host(
  Widget child, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: SizedBox.expand(child: child)),
    ),
  );
}

AnimatedSwitcher _switcherOf(WidgetTester tester) {
  return tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
}

void main() {
  group('AmbientBackdrop', () {
    testWidgets('renders the blur via ImageFiltered, not BackdropFilter',
        (tester) async {
      await mockNetworkImages(() async {
        await tester.pumpWidget(
          _host(const AmbientBackdrop(
            imageUrl: 'https://example.com/a.jpg',
            id: 'a',
          )),
        );
        await tester.pump();

        expect(find.byType(ImageFiltered), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
      });
    });

    testWidgets('null imageUrl renders the static fallback (no image)',
        (tester) async {
      await tester.pumpWidget(_host(const AmbientBackdrop()));
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('changing the id key triggers an AnimatedSwitcher transition',
        (tester) async {
      await mockNetworkImages(() async {
        await tester.pumpWidget(
          _host(const AmbientBackdrop(
            imageUrl: 'https://example.com/a.jpg',
            id: 'a',
          )),
        );
        await tester.pump();

        // Swap the id -> a new keyed child; the switcher keeps both layers
        // present mid-fade.
        await tester.pumpWidget(
          _host(const AmbientBackdrop(
            imageUrl: 'https://example.com/b.jpg',
            id: 'b',
          )),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Two artwork layers exist mid-transition (outgoing + incoming).
        expect(find.byType(CachedNetworkImage), findsNWidgets(2));

        // Settle to a single layer.
        await tester.pumpAndSettle();
        expect(find.byType(CachedNetworkImage), findsOneWidget);
      });
    });

    testWidgets('same id with unchanged params does not transition',
        (tester) async {
      await mockNetworkImages(() async {
        await tester.pumpWidget(
          _host(const AmbientBackdrop(
            imageUrl: 'https://example.com/a.jpg',
            id: 'a',
          )),
        );
        await tester.pump();

        // Rebuild with identical id/url.
        await tester.pumpWidget(
          _host(const AmbientBackdrop(
            imageUrl: 'https://example.com/a.jpg',
            id: 'a',
          )),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // No second layer spawned.
        expect(find.byType(CachedNetworkImage), findsOneWidget);
      });
    });

    testWidgets('with reduced motion on, the crossfade duration is zero',
        (tester) async {
      await mockNetworkImages(() async {
        await tester.pumpWidget(
          _host(
            const AmbientBackdrop(
              imageUrl: 'https://example.com/a.jpg',
              id: 'a',
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump();

        expect(_switcherOf(tester).duration, Duration.zero);
      });
    });

    testWidgets('with motion allowed, the crossfade duration is non-zero',
        (tester) async {
      await mockNetworkImages(() async {
        await tester.pumpWidget(
          _host(const AmbientBackdrop(
            imageUrl: 'https://example.com/a.jpg',
            id: 'a',
          )),
        );
        await tester.pump();

        expect(_switcherOf(tester).duration, greaterThan(Duration.zero));
      });
    });
  });
}
