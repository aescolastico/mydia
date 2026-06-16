import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:media_kit/media_kit.dart';

import '../../graphql/mutations/update_movie_progress.graphql.dart';
import '../../graphql/mutations/update_episode_progress.graphql.dart';
import 'duration_override.dart';

/// Service for syncing playback progress to the server.
///
/// Handles periodic progress updates during playback and saves
/// final position when playback stops.
class ProgressService {
  final GraphQLClient _client;
  Timer? _syncTimer;
  DateTime? _lastSyncTime;

  static const _syncInterval = Duration(seconds: 10);
  static const _watchedThreshold = 0.90; // 90% completion

  ProgressService(this._client);

  /// Starts syncing progress for a movie.
  ///
  /// Updates progress every 10 seconds while playing.
  void startMovieSync(
    Player player,
    String movieId,
  ) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      _syncMovieProgress(player, movieId);
    });
  }

  /// Starts syncing progress for an episode.
  ///
  /// Updates progress every 10 seconds while playing.
  void startEpisodeSync(
    Player player,
    String episodeId,
  ) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      _syncEpisodeProgress(player, episodeId);
    });
  }

  /// Stops the periodic sync timer.
  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Saves movie progress immediately (call on pause/exit).
  Future<void> saveMovieProgress(
    Player player,
    String movieId,
  ) async {
    await _syncMovieProgress(player, movieId);
  }

  /// Saves episode progress immediately (call on pause/exit).
  Future<void> saveEpisodeProgress(
    Player player,
    String episodeId,
  ) async {
    await _syncEpisodeProgress(player, episodeId);
  }

  /// Resolves the position/duration to sync, preferring the authoritative
  /// [DurationOverride] over the player's live duration.
  ///
  /// During HLS transcode the player reports a partial, still-growing
  /// duration (the playlist is built incrementally and the transcoder runs
  /// faster than realtime). Computing progress against it inflates the
  /// completion percentage — a few seconds of playback can read as ~30%.
  /// The override carries the true full media duration.
  ///
  /// Returns null when the data isn't valid to sync yet: duration unknown
  /// (still loading, failed load, error state — the server requires
  /// duration > 0), or position out of range.
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

  Future<void> _syncMovieProgress(
    Player player,
    String movieId,
  ) async {
    final progress = resolveSync(player.state.position, player.state.duration);
    if (progress == null) {
      debugPrint('[ProgressService] Skipping movie sync: invalid position/duration');
      return;
    }

    // Avoid syncing too frequently
    if (_lastSyncTime != null &&
        DateTime.now().difference(_lastSyncTime!) < _syncInterval) {
      return;
    }

    try {
      _lastSyncTime = DateTime.now();

      debugPrint('[ProgressService] Syncing movie progress: movieId=$movieId, position=${progress.positionSeconds}, duration=${progress.durationSeconds}');

      final options = MutationOptions(
        document: documentNodeMutationUpdateMovieProgress,
        variables: Variables$Mutation$UpdateMovieProgress(
          movieId: movieId,
          positionSeconds: progress.positionSeconds,
          durationSeconds: progress.durationSeconds,
        ).toJson(),
      );

      final result = await _client.mutate(options);

      if (result.hasException) {
        debugPrint('[ProgressService] Error syncing movie progress: ${result.exception}');
      } else {
        debugPrint('[ProgressService] Movie progress synced successfully');
      }
    } catch (e) {
      debugPrint('[ProgressService] Exception syncing movie progress: $e');
    }
  }

  Future<void> _syncEpisodeProgress(
    Player player,
    String episodeId,
  ) async {
    final progress = resolveSync(player.state.position, player.state.duration);
    if (progress == null) {
      debugPrint('[ProgressService] Skipping episode sync: invalid position/duration');
      return;
    }

    // Avoid syncing too frequently
    if (_lastSyncTime != null &&
        DateTime.now().difference(_lastSyncTime!) < _syncInterval) {
      return;
    }

    try {
      _lastSyncTime = DateTime.now();

      debugPrint('[ProgressService] Syncing episode progress: episodeId=$episodeId, position=${progress.positionSeconds}, duration=${progress.durationSeconds}');

      final options = MutationOptions(
        document: documentNodeMutationUpdateEpisodeProgress,
        variables: Variables$Mutation$UpdateEpisodeProgress(
          episodeId: episodeId,
          positionSeconds: progress.positionSeconds,
          durationSeconds: progress.durationSeconds,
        ).toJson(),
      );

      final result = await _client.mutate(options);

      if (result.hasException) {
        debugPrint('[ProgressService] Error syncing episode progress: ${result.exception}');
      } else {
        debugPrint('[ProgressService] Episode progress synced successfully');
      }
    } catch (e) {
      debugPrint('[ProgressService] Exception syncing episode progress: $e');
    }
  }

  /// Checks if the current playback position indicates the content is watched.
  ///
  /// Returns true if position is >= 90% of duration.
  bool isWatched(Player player) {
    final position = player.state.position.inSeconds;
    final duration =
        DurationOverride.getDuration(player.state.duration).inSeconds;

    if (duration <= 0) return false;

    return (position / duration) >= _watchedThreshold;
  }

  /// Disposes the service and cancels any active timers.
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}
