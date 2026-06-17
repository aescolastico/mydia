import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ambient_backdrop_provider.g.dart';

/// The artwork source the shell-level [AmbientBackdrop] should render.
///
/// A null [imageUrl] means "no per-title artwork" — the backdrop shows its calm
/// static fallback (grids, settings). [id] is the stable identity used to key
/// the crossfade so equal sources don't re-trigger a transition.
@immutable
class BackdropSource {
  final String? imageUrl;
  final String? id;

  const BackdropSource({this.imageUrl, this.id});

  /// The static-fallback source (no artwork).
  static const BackdropSource none = BackdropSource();

  @override
  bool operator ==(Object other) =>
      other is BackdropSource &&
      other.imageUrl == imageUrl &&
      other.id == id;

  @override
  int get hashCode => Object.hash(imageUrl, id);
}

/// Carries the current shell backdrop source.
///
/// Browse screens publish their source from `build` (home -> its hero pick;
/// grids/settings -> [BackdropSource.none]). The [AmbientBackdrop] in the shell
/// watches this and crossfades when it changes.
///
/// Screens publish via a post-frame callback so they don't mutate provider
/// state synchronously during their own build.
@riverpod
class AmbientBackdropController extends _$AmbientBackdropController {
  @override
  BackdropSource build() => BackdropSource.none;

  /// Sets the backdrop source. No-op when the source is unchanged so we don't
  /// retrigger the crossfade on every rebuild.
  void set(BackdropSource source) {
    if (state != source) {
      state = source;
    }
  }

  /// Clears to the static fallback.
  void clear() => set(BackdropSource.none);
}

/// Publishes [source] as the shell backdrop after the current frame.
///
/// Browse screens call this from `build` so they don't mutate provider state
/// synchronously while building (which Riverpod disallows). Grid/settings
/// screens pass [BackdropSource.none] to show the calm static fallback.
void publishBackdropSource(WidgetRef ref, BackdropSource source) {
  // Skip scheduling entirely when the published source is already identical.
  // Many screens call this unconditionally from `build`, so without this guard
  // every rebuild (scroll, hover, animation) would enqueue a redundant
  // post-frame callback. A cheap read-and-compare avoids that churn.
  if (ref.read(ambientBackdropControllerProvider) == source) return;

  SchedulerBinding.instance.addPostFrameCallback((_) {
    // The ref may have been disposed if the screen left the tree before the
    // post-frame callback ran; guard against that.
    if (!ref.context.mounted) return;
    ref.read(ambientBackdropControllerProvider.notifier).set(source);
  });
}
