import 'package:flutter/foundation.dart';

import '../../domain/models/download.dart';
import '../../domain/models/episode.dart';
import '../../domain/models/movie_detail.dart';
import 'download_job_service.dart';
import 'download_service.dart';

/// Result of a bulk download operation.
class BulkDownloadResult {
  final int queued;
  final int skipped;
  final int failed;

  const BulkDownloadResult({
    required this.queued,
    required this.skipped,
    required this.failed,
  });

  int get total => queued + skipped + failed;
}

/// Queues downloads for a list of episodes, skipping already downloaded
/// or in-queue episodes.
///
/// Returns a [BulkDownloadResult] with counts of queued, skipped, and failed.
Future<BulkDownloadResult> startBulkEpisodeDownloads({
  required List<Episode> episodes,
  required String resolution,
  required String showId,
  required String showTitle,
  required String? showPosterUrl,
  required DownloadService downloadManager,
  required DownloadJobService downloadJobService,
  required bool Function(String mediaId) isMediaDownloaded,
  required bool Function(String mediaId) isMediaInQueue,
}) async {
  int queued = 0;
  int skipped = 0;
  int failed = 0;

  for (final episode in episodes) {
    // Skip already downloaded or queued episodes
    if (isMediaDownloaded(episode.id) || isMediaInQueue(episode.id)) {
      skipped++;
      continue;
    }

    try {
      await downloadManager.startProgressiveDownload(
        mediaId: episode.id,
        title: '$showTitle - ${episode.episodeCode}: ${episode.title}',
        contentType: 'episode',
        resolution: resolution,
        mediaType: MediaType.episode,
        posterUrl: episode.thumbnailUrl,
        overview: episode.overview,
        runtime: episode.runtime,
        seasonNumber: episode.seasonNumber,
        episodeNumber: episode.episodeNumber,
        showId: showId,
        showTitle: showTitle,
        showPosterUrl: showPosterUrl,
        thumbnailUrl: episode.thumbnailUrl,
        airDate: episode.airDate,
        getDownloadUrl: (jobId) async {
          return await downloadJobService.getDownloadUrl(jobId);
        },
        prepareDownload: () async {
          final status = await downloadJobService.prepareDownload(
            contentType: 'episode',
            id: episode.id,
            resolution: resolution,
          );
          return (
            jobId: status.jobId,
            status: status.status.name,
            progress: status.progress,
            fileSize: status.currentFileSize,
          );
        },
        getJobStatus: (jobId) async {
          final status = await downloadJobService.getJobStatus(jobId);
          return (
            status: status.status.name,
            progress: status.progress,
            fileSize: status.currentFileSize,
            error: status.error,
          );
        },
        cancelJob: (jobId) async {
          await downloadJobService.cancelJob(jobId);
        },
      );
      queued++;
    } catch (e) {
      debugPrint('Failed to queue download for ${episode.episodeCode}: $e');
      failed++;
    }
  }

  return BulkDownloadResult(queued: queued, skipped: skipped, failed: failed);
}

/// Queues downloads for a list of movies, skipping already downloaded
/// or in-queue movies.
///
/// Returns a [BulkDownloadResult] with counts of queued, skipped, and failed.
Future<BulkDownloadResult> startBulkMovieDownloads({
  required List<MovieDetail> movies,
  required String resolution,
  required DownloadService downloadManager,
  required DownloadJobService downloadJobService,
  required bool Function(String mediaId) isMediaDownloaded,
  required bool Function(String mediaId) isMediaInQueue,
}) async {
  int queued = 0;
  int skipped = 0;
  int failed = 0;

  for (final movie in movies) {
    // Skip already downloaded or queued movies
    if (isMediaDownloaded(movie.id) || isMediaInQueue(movie.id)) {
      skipped++;
      continue;
    }

    try {
      await downloadManager.startProgressiveDownload(
        mediaId: movie.id,
        title: movie.title,
        contentType: 'movie',
        resolution: resolution,
        mediaType: MediaType.movie,
        posterUrl: movie.artwork.posterUrl,
        overview: movie.overview,
        runtime: movie.runtime,
        genres: movie.genres,
        rating: movie.rating,
        backdropUrl: movie.artwork.backdropUrl,
        year: movie.year,
        contentRating: movie.contentRating,
        getDownloadUrl: (jobId) async {
          return await downloadJobService.getDownloadUrl(jobId);
        },
        prepareDownload: () async {
          final status = await downloadJobService.prepareDownload(
            contentType: 'movie',
            id: movie.id,
            resolution: resolution,
          );
          return (
            jobId: status.jobId,
            status: status.status.name,
            progress: status.progress,
            fileSize: status.currentFileSize,
          );
        },
        getJobStatus: (jobId) async {
          final status = await downloadJobService.getJobStatus(jobId);
          return (
            status: status.status.name,
            progress: status.progress,
            fileSize: status.currentFileSize,
            error: status.error,
          );
        },
        cancelJob: (jobId) async {
          await downloadJobService.cancelJob(jobId);
        },
      );
      queued++;
    } catch (e) {
      debugPrint('Failed to queue download for movie ${movie.title}: $e');
      failed++;
    }
  }

  return BulkDownloadResult(queued: queued, skipped: skipped, failed: failed);
}
