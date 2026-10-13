import 'package:embyplayer/src/features/people/data/actor_favorites_store.dart';
import 'package:embyplayer/src/features/people/domain/actor_favorite.dart';
import 'package:embyplayer/src/features/people/presentation/actor_favorites_provider.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final samplePerson = MediaPerson(
    id: 'actor-999',
    name: 'Christopher Nolan',
    type: 'Director',
    role: 'Director',
    imageUri: Uri.parse('http://127.0.0.1:8096/Items/actor-999/Images/Primary'),
  );

  test('ActorFavorite model serialization and conversion', () {
    final fav = ActorFavorite.fromMediaPerson(samplePerson);
    expect(fav.id, 'actor-999');
    expect(fav.name, 'Christopher Nolan');

    final json = fav.toJson();
    expect(json['id'], 'actor-999');

    final decoded = ActorFavorite.fromJson(json);
    expect(decoded.id, 'actor-999');
    expect(decoded.name, 'Christopher Nolan');

    final mediaPerson = decoded.toMediaPerson();
    expect(mediaPerson.id, 'actor-999');
    expect(mediaPerson.name, 'Christopher Nolan');
  });

  test('MemoryActorFavoritesStore reads and writes favorites', () async {
    final store = MemoryActorFavoritesStore();
    final fav = ActorFavorite.fromMediaPerson(samplePerson);

    await store.writeFavorites([fav]);
    final list = await store.readFavorites();

    expect(list.length, 1);
    expect(list.first.id, 'actor-999');
  });

  test('ActorFavoritesNotifier toggles favorite state', () async {
    final store = MemoryActorFavoritesStore();
    final container = ProviderContainer(
      overrides: [actorFavoritesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(actorFavoritesProvider.notifier);
    final fav = ActorFavorite.fromMediaPerson(samplePerson);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.isFavorite('actor-999'), isFalse);

    final added = await notifier.toggleFavorite(fav);
    expect(added, isTrue);
    expect(notifier.isFavorite('actor-999'), isTrue);

    final removed = await notifier.toggleFavorite(fav);
    expect(removed, isFalse);
    expect(notifier.isFavorite('actor-999'), isFalse);
  });
}
