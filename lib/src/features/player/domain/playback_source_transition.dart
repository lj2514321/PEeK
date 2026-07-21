enum PlaybackSourceTransitionStatus {
  switched,
  preparationFailed,
  restored,
  restoreFailed,
}

class PlaybackSourceTransitionResult<T> {
  const PlaybackSourceTransitionResult({
    required this.status,
    this.value,
    this.error,
    this.restoreError,
  });

  final PlaybackSourceTransitionStatus status;
  final T? value;
  final Object? error;
  final Object? restoreError;
}

class PlaybackSourceTransition {
  const PlaybackSourceTransition();

  Future<PlaybackSourceTransitionResult<T>> execute<T>({
    required Future<T> Function() prepare,
    required Future<void> Function(T value) open,
    required Future<void> Function() restore,
  }) async {
    late final T value;
    try {
      value = await prepare();
    } on Object catch (error) {
      return PlaybackSourceTransitionResult(
        status: PlaybackSourceTransitionStatus.preparationFailed,
        error: error,
      );
    }

    try {
      await open(value);
      return PlaybackSourceTransitionResult(
        status: PlaybackSourceTransitionStatus.switched,
        value: value,
      );
    } on Object catch (error) {
      try {
        await restore();
        return PlaybackSourceTransitionResult(
          status: PlaybackSourceTransitionStatus.restored,
          error: error,
        );
      } on Object catch (restoreError) {
        return PlaybackSourceTransitionResult(
          status: PlaybackSourceTransitionStatus.restoreFailed,
          error: error,
          restoreError: restoreError,
        );
      }
    }
  }
}
