enum PlaybackBitrate {
  original(160000000, '原画优先', '160 Mbps'),
  mbps120(120000000, '超高画质', '120 Mbps'),
  mbps80(80000000, '4K', '80 Mbps'),
  mbps40(40000000, '高画质', '40 Mbps'),
  mbps20(20000000, '平衡', '20 Mbps'),
  mbps10(10000000, '流畅', '10 Mbps'),
  mbps5(5000000, '节省流量', '5 Mbps');

  const PlaybackBitrate(this.bitsPerSecond, this.label, this.detail);

  final int bitsPerSecond;
  final String label;
  final String detail;

  String get compactLabel =>
      this == original ? '原画' : '${bitsPerSecond ~/ 1000000}M';

  static PlaybackBitrate fromName(Object? value) {
    return values.where((item) => item.name == value).firstOrNull ?? original;
  }
}

enum HardwareDecodingMode {
  automatic('auto-safe', '自动硬件解码', '推荐 · 不支持时回退软件解码'),
  software('no', '软件解码', '兼容模式 · CPU 占用更高');

  const HardwareDecodingMode(this.mpvValue, this.label, this.detail);

  final String mpvValue;
  final String label;
  final String detail;

  static HardwareDecodingMode fromName(Object? value) {
    return values.where((item) => item.name == value).firstOrNull ?? automatic;
  }
}

enum SubtitleAppearance {
  cinema('影院白'),
  warm('暖黄'),
  highContrast('高对比');

  const SubtitleAppearance(this.label);

  final String label;

  static SubtitleAppearance fromName(Object? value) {
    return values.where((item) => item.name == value).firstOrNull ?? cinema;
  }
}

class SubtitlePreferences {
  const SubtitlePreferences({
    this.appearance = SubtitleAppearance.cinema,
    this.fontSize = 25,
    this.bottomPadding = 94,
    this.delayMilliseconds = 0,
  });

  final SubtitleAppearance appearance;
  final double fontSize;
  final double bottomPadding;
  final int delayMilliseconds;

  Duration get delay => Duration(milliseconds: delayMilliseconds);

  SubtitlePreferences copyWith({
    SubtitleAppearance? appearance,
    double? fontSize,
    double? bottomPadding,
    int? delayMilliseconds,
  }) {
    return SubtitlePreferences(
      appearance: appearance ?? this.appearance,
      fontSize: fontSize ?? this.fontSize,
      bottomPadding: bottomPadding ?? this.bottomPadding,
      delayMilliseconds: delayMilliseconds ?? this.delayMilliseconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'appearance': appearance.name,
    'fontSize': fontSize,
    'bottomPadding': bottomPadding,
    'delayMilliseconds': delayMilliseconds,
  };

  factory SubtitlePreferences.fromJson(Object? value) {
    if (value is! Map) return const SubtitlePreferences();
    final json = Map<Object?, Object?>.from(value);
    final rawFontSize = json['fontSize'];
    final rawBottomPadding = json['bottomPadding'];
    final rawDelay = json['delayMilliseconds'];
    return SubtitlePreferences(
      appearance: SubtitleAppearance.fromName(json['appearance']),
      fontSize: rawFontSize is num ? rawFontSize.toDouble().clamp(18, 42) : 25,
      bottomPadding: rawBottomPadding is num
          ? rawBottomPadding.toDouble().clamp(48, 180)
          : 94,
      delayMilliseconds: rawDelay is num
          ? rawDelay.toInt().clamp(-10000, 10000)
          : 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SubtitlePreferences &&
        other.appearance == appearance &&
        other.fontSize == fontSize &&
        other.bottomPadding == bottomPadding &&
        other.delayMilliseconds == delayMilliseconds;
  }

  @override
  int get hashCode =>
      Object.hash(appearance, fontSize, bottomPadding, delayMilliseconds);
}

class SkipIntroPreferences {
  const SkipIntroPreferences({
    this.enabled = true,
    this.autoSkip = true,
    this.countdownSeconds = 3,
    this.fallbackIntroSeconds = 90,
    this.fallbackOutroSeconds = 90,
  });

  final bool enabled;
  final bool autoSkip;
  final int countdownSeconds;
  final int fallbackIntroSeconds;
  final int fallbackOutroSeconds;

  SkipIntroPreferences copyWith({
    bool? enabled,
    bool? autoSkip,
    int? countdownSeconds,
    int? fallbackIntroSeconds,
    int? fallbackOutroSeconds,
  }) {
    return SkipIntroPreferences(
      enabled: enabled ?? this.enabled,
      autoSkip: autoSkip ?? this.autoSkip,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      fallbackIntroSeconds: fallbackIntroSeconds ?? this.fallbackIntroSeconds,
      fallbackOutroSeconds: fallbackOutroSeconds ?? this.fallbackOutroSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'autoSkip': autoSkip,
    'countdownSeconds': countdownSeconds,
    'fallbackIntroSeconds': fallbackIntroSeconds,
    'fallbackOutroSeconds': fallbackOutroSeconds,
  };

  factory SkipIntroPreferences.fromJson(Object? value) {
    if (value is! Map) return const SkipIntroPreferences();
    final json = Map<Object?, Object?>.from(value);
    return SkipIntroPreferences(
      enabled: json['enabled'] as bool? ?? true,
      autoSkip: json['autoSkip'] as bool? ?? true,
      countdownSeconds: (json['countdownSeconds'] as num?)?.toInt() ?? 3,
      fallbackIntroSeconds:
          (json['fallbackIntroSeconds'] as num?)?.toInt() ?? 90,
      fallbackOutroSeconds:
          (json['fallbackOutroSeconds'] as num?)?.toInt() ?? 90,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkipIntroPreferences &&
      other.enabled == enabled &&
      other.autoSkip == autoSkip &&
      other.countdownSeconds == countdownSeconds &&
      other.fallbackIntroSeconds == fallbackIntroSeconds &&
      other.fallbackOutroSeconds == fallbackOutroSeconds;

  @override
  int get hashCode => Object.hash(
    enabled,
    autoSkip,
    countdownSeconds,
    fallbackIntroSeconds,
    fallbackOutroSeconds,
  );
}

class DanmakuPreferences {
  const DanmakuPreferences({
    this.enabled = true,
    this.offsetMilliseconds = 0,
    this.opacity = 0.85,
    this.fontSize = 16.0,
    this.displayArea = 0.5,
    this.blockedKeywords = const [],
    this.preventSubtitleOverlap = true,
    this.allowScroll = true,
    this.allowTop = true,
    this.allowBottom = true,
  });

  final bool enabled;
  final int offsetMilliseconds;
  final double opacity;
  final double fontSize;
  final double displayArea;
  final List<String> blockedKeywords;
  final bool preventSubtitleOverlap;
  final bool allowScroll;
  final bool allowTop;
  final bool allowBottom;

  DanmakuPreferences copyWith({
    bool? enabled,
    int? offsetMilliseconds,
    double? opacity,
    double? fontSize,
    double? displayArea,
    List<String>? blockedKeywords,
    bool? preventSubtitleOverlap,
    bool? allowScroll,
    bool? allowTop,
    bool? allowBottom,
  }) {
    return DanmakuPreferences(
      enabled: enabled ?? this.enabled,
      offsetMilliseconds: offsetMilliseconds ?? this.offsetMilliseconds,
      opacity: opacity ?? this.opacity,
      fontSize: fontSize ?? this.fontSize,
      displayArea: displayArea ?? this.displayArea,
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      preventSubtitleOverlap:
          preventSubtitleOverlap ?? this.preventSubtitleOverlap,
      allowScroll: allowScroll ?? this.allowScroll,
      allowTop: allowTop ?? this.allowTop,
      allowBottom: allowBottom ?? this.allowBottom,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'offsetMilliseconds': offsetMilliseconds,
    'opacity': opacity,
    'fontSize': fontSize,
    'displayArea': displayArea,
    'blockedKeywords': blockedKeywords,
    'preventSubtitleOverlap': preventSubtitleOverlap,
    'allowScroll': allowScroll,
    'allowTop': allowTop,
    'allowBottom': allowBottom,
  };

  factory DanmakuPreferences.fromJson(Object? value) {
    if (value is! Map) return const DanmakuPreferences();
    final json = Map<Object?, Object?>.from(value);
    final rawList = json['blockedKeywords'];
    final blocked = rawList is List
        ? rawList
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return DanmakuPreferences(
      enabled: json['enabled'] as bool? ?? true,
      offsetMilliseconds: (json['offsetMilliseconds'] as num?)?.toInt() ?? 0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.85,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
      displayArea: (json['displayArea'] as num?)?.toDouble() ?? 0.5,
      blockedKeywords: blocked,
      preventSubtitleOverlap: json['preventSubtitleOverlap'] as bool? ?? true,
      allowScroll: json['allowScroll'] as bool? ?? true,
      allowTop: json['allowTop'] as bool? ?? true,
      allowBottom: json['allowBottom'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DanmakuPreferences &&
      other.enabled == enabled &&
      other.offsetMilliseconds == offsetMilliseconds &&
      other.opacity == opacity &&
      other.fontSize == fontSize &&
      other.displayArea == displayArea &&
      other.preventSubtitleOverlap == preventSubtitleOverlap &&
      other.allowScroll == allowScroll &&
      other.allowTop == allowTop &&
      other.allowBottom == allowBottom;

  @override
  int get hashCode => Object.hash(
    enabled,
    offsetMilliseconds,
    opacity,
    fontSize,
    displayArea,
    preventSubtitleOverlap,
    allowScroll,
    allowTop,
    allowBottom,
  );
}

class PlaybackSettings {
  const PlaybackSettings({
    this.maxStreamingBitrate = PlaybackBitrate.original,
    this.hardwareDecodingMode = HardwareDecodingMode.automatic,
    this.subtitlePreferences = const SubtitlePreferences(),
    this.skipIntroPreferences = const SkipIntroPreferences(),
    this.danmakuPreferences = const DanmakuPreferences(),
    this.enableMiniPlayer = true,
    this.useExternalPlayer = false,
    this.externalPlayerPath,
    this.longPressSpeed = 2.0,
  });

  final PlaybackBitrate maxStreamingBitrate;
  final HardwareDecodingMode hardwareDecodingMode;
  final SubtitlePreferences subtitlePreferences;
  final SkipIntroPreferences skipIntroPreferences;
  final DanmakuPreferences danmakuPreferences;
  final bool enableMiniPlayer;
  final bool useExternalPlayer;
  final String? externalPlayerPath;
  final double longPressSpeed;

  PlaybackSettings copyWith({
    PlaybackBitrate? maxStreamingBitrate,
    HardwareDecodingMode? hardwareDecodingMode,
    SubtitlePreferences? subtitlePreferences,
    SkipIntroPreferences? skipIntroPreferences,
    DanmakuPreferences? danmakuPreferences,
    bool? enableMiniPlayer,
    bool? useExternalPlayer,
    String? externalPlayerPath,
    bool clearExternalPlayerPath = false,
    double? longPressSpeed,
  }) {
    return PlaybackSettings(
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
      hardwareDecodingMode: hardwareDecodingMode ?? this.hardwareDecodingMode,
      subtitlePreferences: subtitlePreferences ?? this.subtitlePreferences,
      skipIntroPreferences: skipIntroPreferences ?? this.skipIntroPreferences,
      danmakuPreferences: danmakuPreferences ?? this.danmakuPreferences,
      enableMiniPlayer: enableMiniPlayer ?? this.enableMiniPlayer,
      useExternalPlayer: useExternalPlayer ?? this.useExternalPlayer,
      externalPlayerPath: clearExternalPlayerPath
          ? null
          : (externalPlayerPath ?? this.externalPlayerPath),
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    );
  }

  Map<String, dynamic> toJson() => {
    'maxStreamingBitrate': maxStreamingBitrate.name,
    'hardwareDecodingMode': hardwareDecodingMode.name,
    'subtitlePreferences': subtitlePreferences.toJson(),
    'skipIntroPreferences': skipIntroPreferences.toJson(),
    'danmakuPreferences': danmakuPreferences.toJson(),
    'enableMiniPlayer': enableMiniPlayer,
    'useExternalPlayer': useExternalPlayer,
    'externalPlayerPath': externalPlayerPath,
    'longPressSpeed': longPressSpeed,
  };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      maxStreamingBitrate: PlaybackBitrate.fromName(
        json['maxStreamingBitrate'],
      ),
      hardwareDecodingMode: HardwareDecodingMode.fromName(
        json['hardwareDecodingMode'],
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
      enableMiniPlayer: json['enableMiniPlayer'] as bool? ?? true,
      useExternalPlayer: json['useExternalPlayer'] as bool? ?? false,
      externalPlayerPath: json['externalPlayerPath'] as String?,
      longPressSpeed: (json['longPressSpeed'] as num?)?.toDouble() ?? 2.0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaybackSettings &&
        other.maxStreamingBitrate == maxStreamingBitrate &&
        other.hardwareDecodingMode == hardwareDecodingMode &&
        other.subtitlePreferences == subtitlePreferences &&
        other.skipIntroPreferences == skipIntroPreferences &&
        other.danmakuPreferences == danmakuPreferences &&
        other.enableMiniPlayer == enableMiniPlayer &&
        other.useExternalPlayer == useExternalPlayer &&
        other.externalPlayerPath == externalPlayerPath &&
        other.longPressSpeed == longPressSpeed;
  }

  @override
  int get hashCode => Object.hash(
    maxStreamingBitrate,
    hardwareDecodingMode,
    subtitlePreferences,
    skipIntroPreferences,
    danmakuPreferences,
    enableMiniPlayer,
    useExternalPlayer,
    externalPlayerPath,
    longPressSpeed,
  );
}
