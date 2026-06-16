---
title: Playback progress inflated by partial HLS transcode duration
date: 2026-06-16
category: docs/solutions/logic-errors
module: Flutter player — playback progress
problem_type: logic_error
component: service_object
symptoms:
  - "A few seconds of HLS playback shows as ~30% watched on episode/home cards"
  - "Items flip to watched / show Up-Next far too early"
  - "Inflated completion percentage is persisted to the backend playback_progress row"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [player, playback-progress, hls, transcode, duration, flutter, watched-threshold]
---

# Playback progress inflated by partial HLS transcode duration

## Problem

In the Flutter player, playback progress was computed against `player.state.duration`. During HLS transcode that value is the partial, still-growing playlist length — not the full media duration — so a few seconds of playback was reported as ~30% complete, inflating progress on episode/home cards and tripping the 90% "watched" threshold early.

## Symptoms

- A few seconds of HLS playback reads as ~30% on episode and home cards.
- Episodes flip to "watched" / show the Up-Next overlay prematurely.
- The inflated percentage is persisted (the `playback_progress` row's `completion_percentage` and `duration_seconds` are wrong while transcoding).

## What Didn't Work

- **Suspecting the backend math.** `lib/mydia/playback/progress.ex` computes `position / duration * 100.0` correctly; a live DB row (`position=1787s`, `duration=3452s`, `51.8%`) was internally consistent. The backend was never wrong.
- **Suspecting position ran ahead (live-edge start).** Hypothesized the player began at the HLS live edge. Refuted by observation: a row captured mid-playback showed `position=1787s` at ~30 minutes watched — position tracking is accurate. Re-querying the live DB killed the theory.

## Solution

`player.state.duration` is unreliable during HLS transcode. The player already carries the true full duration in `DurationOverride` (set from streaming-candidate / session metadata, and used by the seekbar). `ProgressService` was reading the raw player duration directly instead.

Route progress sync and the watched check through `DurationOverride.getDuration()`, which returns the override when it exceeds the player's live duration:

```dart
// player/lib/core/player/progress_service.dart

// Resolves the duration to sync against, preferring the authoritative
// DurationOverride over the player's live (partial, growing) HLS duration.
static ({int positionSeconds, int durationSeconds})? resolveSync(
  Duration position,
  Duration playerDuration,
) {
  final duration = DurationOverride.getDuration(playerDuration).inSeconds;
  final pos = position.inSeconds;
  if (duration <= 0) return null;
  if (pos < 0 || pos > duration) return null;
  return (positionSeconds: pos, durationSeconds: duration);
}

bool isWatched(Player player) {
  final duration =
      DurationOverride.getDuration(player.state.duration).inSeconds;
  if (duration <= 0) return false;
  return (player.state.position.inSeconds / duration) >= _watchedThreshold;
}
```

Both `_syncMovieProgress` and `_syncEpisodeProgress` call `resolveSync`. Fixed in PR #206.

## Why This Works

The HLS transcoder serves a **live/growing** playlist (`lib/mydia/streaming/ffmpeg_hls_transcoder.ex:557`: `-f hls -hls_time 4 -hls_list_size 0`, no `-hls_playlist_type`, no `EXT-X-ENDLIST` until complete). libmpv/media_kit therefore reports the *currently-available* duration, which grows as segments are appended. Because the transcoder runs faster than realtime, `position / player.state.duration ≈ 1 / transcode_speed` (a 3× transcode → ~33%). Using `DurationOverride` — the real full media length — makes the ratio correct, and it self-corrects once transcoding completes and `player.state.duration` finally equals the full length.

## Prevention

- **Never read `player.state.duration` directly for progress/percentage math during HLS playback** — always resolve through `DurationOverride.getDuration(player.state.duration)`. Any new code (overlays, analytics, resume logic) that reads player duration can repeat this miss.
- Unit test the transcode case against a pure helper rather than the un-mockable media_kit `Player`: see `player/test/core/player/progress_service_test.dart` — with `DurationOverride.value = 3452s` and a partial player duration of `120s`, `resolveSync` must return `durationSeconds == 3452`, not `120`.

## Related Issues

- PR #206 — the fix.
- Follow-up (separate, unconfirmed): resume seek lands too far forward — likely the resume seek clamping to the live edge because the freshly-restarted from-0 transcode hasn't produced the target segments yet (no `-ss` resume-offset support on the backend).
