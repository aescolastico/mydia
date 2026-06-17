import 'package:flutter_test/flutter_test.dart';
import 'package:player/presentation/screens/home_screen.dart';

void main() {
  group('homeHeroParallaxOffset', () {
    test('shifts proportionally with scroll offset', () {
      final atZero = homeHeroParallaxOffset(0, reduceMotion: false);
      final atSome = homeHeroParallaxOffset(50, reduceMotion: false);
      final atMore = homeHeroParallaxOffset(100, reduceMotion: false);

      expect(atZero, 0);
      // Image translates upward (negative) as the user scrolls down.
      expect(atSome, lessThan(0));
      // More scroll -> more (more-negative) translation, until clamped.
      expect(atMore, lessThan(atSome));
    });

    test('is static (zero) across all offsets under reduced motion', () {
      for (final offset in const [0.0, 50.0, 200.0, 1000.0, -300.0]) {
        expect(
          homeHeroParallaxOffset(offset, reduceMotion: true),
          0,
          reason: 'offset $offset should not parallax under reduced motion',
        );
      }
    });

    test('is bounded to ±homeHeroMaxParallax so no edge gap is exposed', () {
      // Extreme positive and negative scroll never exceed the over-size budget.
      expect(
        homeHeroParallaxOffset(100000, reduceMotion: false),
        greaterThanOrEqualTo(-homeHeroMaxParallax),
      );
      expect(
        homeHeroParallaxOffset(-100000, reduceMotion: false),
        lessThanOrEqualTo(homeHeroMaxParallax),
      );
      // At a large positive scroll it saturates at the lower bound.
      expect(
        homeHeroParallaxOffset(100000, reduceMotion: false),
        -homeHeroMaxParallax,
      );
    });
  });
}
