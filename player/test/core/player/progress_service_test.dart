import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/player/duration_override.dart';
import 'package:player/core/player/progress_service.dart';

void main() {
  // DurationOverride is global state; reset around every test.
  setUp(DurationOverride.clear);
  tearDown(DurationOverride.clear);

  group('ProgressService.resolveSync', () {
    test(
        'uses the authoritative override, not the partial HLS duration '
        '(regression: a few seconds must not read as ~30%)', () {
      // During HLS transcode the player reports a partial, growing duration
      // while the override carries the true full media length.
      DurationOverride.value = const Duration(seconds: 3452);

      final progress = ProgressService.resolveSync(
        const Duration(seconds: 12), // a few seconds watched
        const Duration(seconds: 40), // partial transcoded length so far
      );

      expect(progress, isNotNull);
      // Without the fix, duration would be 40 → 12/40 = 30% (inflated).
      expect(progress!.durationSeconds, 3452);
      expect(progress.positionSeconds, 12);
      // Sanity: the resulting completion fraction is tiny, as it should be.
      expect(progress.positionSeconds / progress.durationSeconds,
          lessThan(0.01));
    });

    test('falls back to the player duration when no override is set', () {
      final progress = ProgressService.resolveSync(
        const Duration(seconds: 600),
        const Duration(seconds: 3452),
      );

      expect(progress, isNotNull);
      expect(progress!.durationSeconds, 3452);
      expect(progress.positionSeconds, 600);
    });

    test('ignores an override that is smaller than the player duration', () {
      // getDuration only prefers the override when it exceeds the player
      // duration, so a stale/smaller override must not shrink a known length.
      DurationOverride.value = const Duration(seconds: 100);

      final progress = ProgressService.resolveSync(
        const Duration(seconds: 600),
        const Duration(seconds: 3452),
      );

      expect(progress!.durationSeconds, 3452);
    });

    test('returns null when duration is unknown (still loading)', () {
      expect(
        ProgressService.resolveSync(Duration.zero, Duration.zero),
        isNull,
      );
    });

    test('returns null when position is out of range', () {
      expect(
        ProgressService.resolveSync(
          const Duration(seconds: 5000),
          const Duration(seconds: 3452),
        ),
        isNull,
      );
    });
  });
}
