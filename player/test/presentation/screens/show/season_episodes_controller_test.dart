import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:player/core/graphql/graphql_provider.dart';
import 'package:player/domain/models/episode.dart';
import 'package:player/domain/models/progress.dart';
import 'package:player/graphql/mutations/mark_watched.graphql.dart';
import 'package:player/presentation/screens/show/season_episodes_controller.dart';

import 'season_episodes_controller_test.mocks.dart';

@GenerateNiceMocks([MockSpec<GraphQLClient>()])
Episode _episode(int number, {bool? watched}) {
  return Episode(
    id: 'ep-$number',
    seasonNumber: 1,
    episodeNumber: number,
    title: 'Episode $number',
    monitored: true,
    hasFile: true,
    progress: watched == null
        ? null
        : Progress(positionSeconds: 0, percentage: 0, watched: watched),
  );
}

Map<String, dynamic> _episodeJson(int number, {bool? watched}) {
  return {
    'id': 'ep-$number',
    'seasonNumber': 1,
    'episodeNumber': number,
    'title': 'Episode $number',
    'monitored': true,
    'hasFile': true,
    'progress': watched == null
        ? null
        : {
            'positionSeconds': 0,
            'durationSeconds': null,
            'percentage': 0,
            'watched': watched,
            'lastWatchedAt': null,
          },
    'files': <dynamic>[],
  };
}

QueryResult _mutationSuccess() => QueryResult(
      options: MutationOptions(document: gql('mutation { x }')),
      source: QueryResultSource.network,
      data: const {},
    );

QueryResult _mutationFailure() => QueryResult(
      options: MutationOptions(document: gql('mutation { x }')),
      source: QueryResultSource.network,
      exception: OperationException(
        graphqlErrors: [const GraphQLError(message: 'boom')],
      ),
    );

void main() {
  group('applyOptimisticWatched (pure subset logic)', () {
    final episodes = [
      _episode(1, watched: true),
      _episode(2),
      _episode(3),
      _episode(4),
      _episode(5),
      _episode(6),
    ];

    test('marking a single episode flips only that episode to watched', () {
      final result = SeasonEpisodesController.applyOptimisticWatched(
        episodes,
        (ep) => ep.id == 'ep-3',
        true,
      );

      expect(result[2].progress?.watched, isTrue);
      // Neighbours untouched.
      expect(result[1].progress, isNull);
      expect(result[3].progress, isNull);
    });

    // Covers AE3.
    test('marking a watched episode unwatched clears its progress', () {
      final result = SeasonEpisodesController.applyOptimisticWatched(
        episodes,
        (ep) => ep.id == 'ep-1',
        false,
      );

      expect(result[0].progress, isNull);
    });

    // Covers AE1.
    test('mark this and previous flips E1..E4 and leaves E5..E6 unchanged', () {
      final result = SeasonEpisodesController.applyOptimisticWatched(
        episodes,
        (ep) => ep.episodeNumber <= 4,
        true,
      );

      for (final ep in result.take(4)) {
        expect(ep.progress?.watched, isTrue, reason: 'E${ep.episodeNumber}');
      }
      expect(result[4].progress, isNull);
      expect(result[5].progress, isNull);
    });

    // Covers AE2.
    test('marking the whole season unwatched clears every progress row', () {
      final result = SeasonEpisodesController.applyOptimisticWatched(
        episodes,
        (_) => true,
        false,
      );

      expect(result.every((ep) => ep.progress == null), isTrue);
    });

    test('marking the whole season watched flips every episode', () {
      final result = SeasonEpisodesController.applyOptimisticWatched(
        episodes,
        (_) => true,
        true,
      );

      expect(result.every((ep) => ep.progress?.watched == true), isTrue);
    });
  });

  group('SeasonEpisodesController watched actions (optimistic + revert)', () {
    late MockGraphQLClient client;

    ProviderContainer makeContainer(List<Map<String, dynamic>> seed) {
      client = MockGraphQLClient();
      when(client.query(any)).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { x }')),
          source: QueryResultSource.network,
          data: {'seasonEpisodes': seed},
        ),
      );

      final container = ProviderContainer(
        overrides: [
          asyncGraphqlClientProvider.overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('markEpisodeWatched flips the target and calls the watched mutation',
        () async {
      final container = makeContainer([
        _episodeJson(1),
        _episodeJson(2),
      ]);
      final provider =
          seasonEpisodesControllerProvider(showId: 'show-1', seasonNumber: 1);

      final episodes = await container.read(provider.future);
      when(client.mutate(any)).thenAnswer((_) async => _mutationSuccess());

      await container
          .read(provider.notifier)
          .markEpisodeWatched(episodes.first);

      final updated = container.read(provider).value!;
      expect(updated.firstWhere((e) => e.id == 'ep-1').progress?.watched,
          isTrue);
      // ep-2 untouched.
      expect(updated.firstWhere((e) => e.id == 'ep-2').progress, isNull);

      final captured =
          verify(client.mutate(captureAny)).captured.single as MutationOptions;
      expect(captured.document, documentNodeMutationMarkEpisodeWatched);
    });

    test('a failed mutation reverts the optimistic state', () async {
      final container = makeContainer([
        _episodeJson(1),
        _episodeJson(2),
      ]);
      final provider =
          seasonEpisodesControllerProvider(showId: 'show-1', seasonNumber: 1);

      final episodes = await container.read(provider.future);
      when(client.mutate(any)).thenAnswer((_) async => _mutationFailure());

      await expectLater(
        container.read(provider.notifier).markEpisodeWatched(episodes.first),
        throwsA(isA<OperationException>()),
      );

      // Reverted: ep-1 has no progress again.
      final reverted = container.read(provider).value!;
      expect(reverted.firstWhere((e) => e.id == 'ep-1').progress, isNull);
    });

    test('markSeasonUnwatched clears every row and calls the season mutation',
        () async {
      final container = makeContainer([
        _episodeJson(1, watched: true),
        _episodeJson(2, watched: true),
      ]);
      final provider =
          seasonEpisodesControllerProvider(showId: 'show-1', seasonNumber: 1);

      await container.read(provider.future);
      when(client.mutate(any)).thenAnswer((_) async => _mutationSuccess());

      await container.read(provider.notifier).markSeasonUnwatched();

      final updated = container.read(provider).value!;
      expect(updated.every((e) => e.progress == null), isTrue);

      final captured =
          verify(client.mutate(captureAny)).captured.single as MutationOptions;
      expect(captured.document, documentNodeMutationMarkSeasonUnwatched);
    });
  });
}
