import 'package:embyplayer/src/features/people/data/actor_favorites_store.dart';
import 'package:embyplayer/src/features/people/domain/actor_favorite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final actorFavoritesStoreProvider = Provider<ActorFavoritesStore>((ref) {
  return LocalActorFavoritesStore();
});

final actorFavoritesProvider =
    NotifierProvider<ActorFavoritesNotifier, AsyncValue<List<ActorFavorite>>>(
  ActorFavoritesNotifier.new,
);

class ActorFavoritesNotifier extends Notifier<AsyncValue<List<ActorFavorite>>> {
  @override
  AsyncValue<List<ActorFavorite>> build() {
    _load();
    return const AsyncValue.loading();
  }

  ActorFavoritesStore get _store => ref.read(actorFavoritesStoreProvider);

  Future<void> _load() async {
    try {
      final list = await _store.readFavorites();
      state = AsyncValue.data(list);
    } on Object catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  bool isFavorite(String actorId) {
    final list = state.value ?? [];
    return list.any((item) => item.id == actorId);
  }

  Future<bool> toggleFavorite(ActorFavorite favorite) async {
    final current = List<ActorFavorite>.from(state.value ?? []);
    final existsIndex = current.indexWhere((item) => item.id == favorite.id);
    final bool isNowFavorite;

    if (existsIndex >= 0) {
      current.removeAt(existsIndex);
      isNowFavorite = false;
    } else {
      current.insert(0, favorite);
      isNowFavorite = true;
    }

    state = AsyncValue.data(List.unmodifiable(current));
    await _store.writeFavorites(current);
    return isNowFavorite;
  }
}
