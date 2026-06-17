import 'progress.dart';
import 'media_file.dart';

class Episode {
  final String id;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final String? overview;
  final String? airDate;
  final int? runtime;
  final bool monitored;
  final String? thumbnailUrl;
  final bool hasFile;
  final Progress? progress;
  final List<MediaFile> files;

  const Episode({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    this.overview,
    this.airDate,
    this.runtime,
    required this.monitored,
    this.thumbnailUrl,
    required this.hasFile,
    this.progress,
    this.files = const [],
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'].toString(),
      seasonNumber: json['seasonNumber'] as int,
      episodeNumber: json['episodeNumber'] as int,
      title: json['title'] as String? ?? 'Episode ${json['episodeNumber']}',
      overview: json['overview'] as String?,
      airDate: json['airDate'] as String?,
      runtime: json['runtime'] as int?,
      monitored: json['monitored'] as bool? ?? false,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      hasFile: json['hasFile'] as bool? ?? false,
      progress: json['progress'] != null
          ? Progress.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// [clearProgress] forces [progress] to null (used when marking unwatched),
  /// since a plain null [progress] argument cannot be distinguished from
  /// "leave unchanged".
  Episode copyWith({
    Progress? progress,
    bool clearProgress = false,
  }) {
    return Episode(
      id: id,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      title: title,
      overview: overview,
      airDate: airDate,
      runtime: runtime,
      monitored: monitored,
      thumbnailUrl: thumbnailUrl,
      hasFile: hasFile,
      progress: clearProgress ? null : (progress ?? this.progress),
      files: files,
    );
  }

  String get episodeCode => 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';

  String get runtimeDisplay {
    if (runtime == null) return '';
    final minutes = runtime!;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}
