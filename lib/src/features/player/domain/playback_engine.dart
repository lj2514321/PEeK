import 'package:embyplayer/src/features/player/domain/playback_plan.dart';

abstract interface class PlaybackEngine {
  Stream<Duration> get position;
  Stream<bool> get playing;

  Future<void> open(PlaybackPlan plan);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}
