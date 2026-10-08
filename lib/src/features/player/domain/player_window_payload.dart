import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/playback_plan.dart';
import 'package:embyplayer/src/core/domain/playback_settings.dart';
import 'package:embyplayer/src/core/domain/server.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';

/// Communication protocol constants for cross-window player interaction.
abstract final class PlayerWindowProtocol {
  static const String channelName = 'peek_player_window';

  // Methods invoked from Main Window -> Player Window
  static const String methodSwitchMedia = 'switchMedia';
  static const String methodPause = 'pause';
  static const String methodResume = 'resume';
  static const String methodSeek = 'seek';
  static const String methodFocus = 'focus';
  static const String methodClose = 'close';

  // Methods invoked from Player Window -> Main Window
  static const String methodReportProgress = 'progress';
  static const String methodReportStateChanged = 'stateChanged';
  static const String methodReportClosed = 'closed';
  static const String methodRequestNext = 'requestNext';
  static const String methodHandoverToMiniPlayer = 'handoverToMiniPlayer';
  static const String methodReportMediaChanged = 'reportMediaChanged';
}

/// The complete initialization & switch payload passed to the Player Window.
class PlayerWindowPayload {
  const PlayerWindowPayload({
    required this.item,
    required this.plan,
    this.account,
    this.queue,
    this.hardwareDecodingMode = HardwareDecodingMode.automatic,
    this.maxStreamingBitrate = PlaybackBitrate.original,
    this.subtitlePreferences = const SubtitlePreferences(),
    this.skipIntroPreferences = const SkipIntroPreferences(),
    this.danmakuPreferences = const DanmakuPreferences(),
    this.longPressSpeed = 2.0,
  });

  final MediaItem item;
  final PlaybackPlan plan;
  final AuthenticatedServer? account;
  final PlaybackQueue? queue;
  final HardwareDecodingMode hardwareDecodingMode;
  final PlaybackBitrate maxStreamingBitrate;
  final SubtitlePreferences subtitlePreferences;
  final SkipIntroPreferences skipIntroPreferences;
  final DanmakuPreferences danmakuPreferences;
  final double longPressSpeed;

  PlayerWindowPayload copyWith({
    MediaItem? item,
    PlaybackPlan? plan,
    AuthenticatedServer? account,
    PlaybackQueue? queue,
    HardwareDecodingMode? hardwareDecodingMode,
    PlaybackBitrate? maxStreamingBitrate,
    SubtitlePreferences? subtitlePreferences,
    SkipIntroPreferences? skipIntroPreferences,
    DanmakuPreferences? danmakuPreferences,
    double? longPressSpeed,
  }) {
    return PlayerWindowPayload(
      item: item ?? this.item,
      plan: plan ?? this.plan,
      account: account ?? this.account,
      queue: queue ?? this.queue,
      hardwareDecodingMode: hardwareDecodingMode ?? this.hardwareDecodingMode,
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
      subtitlePreferences: subtitlePreferences ?? this.subtitlePreferences,
      skipIntroPreferences: skipIntroPreferences ?? this.skipIntroPreferences,
      danmakuPreferences: danmakuPreferences ?? this.danmakuPreferences,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    );
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'plan': plan.toJson(),
    'account': account?.toJson(),
    'queue': queue?.toJson(),
    'hardwareDecodingMode': hardwareDecodingMode.name,
    'maxStreamingBitrate': maxStreamingBitrate.name,
    'subtitlePreferences': subtitlePreferences.toJson(),
    'skipIntroPreferences': skipIntroPreferences.toJson(),
    'danmakuPreferences': danmakuPreferences.toJson(),
    'longPressSpeed': longPressSpeed,
  };

  factory PlayerWindowPayload.fromJson(Map<String, dynamic> json) {
    return PlayerWindowPayload(
      item: MediaItem.fromJson(
        Map<String, dynamic>.from(json['item'] as Map),
      ),
      plan: PlaybackPlan.fromJson(
        Map<String, dynamic>.from(json['plan'] as Map),
      ),
      account: json['account'] != null
          ? AuthenticatedServer.fromJson(
              Map<String, dynamic>.from(json['account'] as Map),
            )
          : null,
      queue: json['queue'] != null
          ? PlaybackQueue.fromJson(
              Map<String, dynamic>.from(json['queue'] as Map),
            )
          : null,
      hardwareDecodingMode: HardwareDecodingMode.values.firstWhere(
        (m) => m.name == json['hardwareDecodingMode'],
        orElse: () => HardwareDecodingMode.automatic,
      ),
      maxStreamingBitrate: PlaybackBitrate.values.firstWhere(
        (b) => b.name == json['maxStreamingBitrate'],
        orElse: () => PlaybackBitrate.original,
      ),
      subtitlePreferences: SubtitlePreferences.fromJson(
        json['subtitlePreferences'],
      ),
      skipIntroPreferences: SkipIntroPreferences.fromJson(
        json['skipIntroPreferences'],
      ),
      danmakuPreferences: DanmakuPreferences.fromJson(
        json['danmakuPreferences'],
      ),
      longPressSpeed: (json['longPressSpeed'] as num?)?.toDouble() ?? 2.0,
    );
  }
}
