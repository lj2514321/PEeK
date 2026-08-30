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

class PlaybackSettings {
  const PlaybackSettings({
    this.maxStreamingBitrate = PlaybackBitrate.original,
    this.hardwareDecodingMode = HardwareDecodingMode.automatic,
    this.subtitlePreferences = const SubtitlePreferences(),
    this.enableMiniPlayer = true,
    this.useExternalPlayer = false,
    this.externalPlayerPath,
  });

  final PlaybackBitrate maxStreamingBitrate;
  final HardwareDecodingMode hardwareDecodingMode;
  final SubtitlePreferences subtitlePreferences;
  final bool enableMiniPlayer;
  final bool useExternalPlayer;
  final String? externalPlayerPath;

  PlaybackSettings copyWith({
    PlaybackBitrate? maxStreamingBitrate,
    HardwareDecodingMode? hardwareDecodingMode,
    SubtitlePreferences? subtitlePreferences,
    bool? enableMiniPlayer,
    bool? useExternalPlayer,
    String? externalPlayerPath,
    bool clearExternalPlayerPath = false,
  }) {
    return PlaybackSettings(
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
      hardwareDecodingMode: hardwareDecodingMode ?? this.hardwareDecodingMode,
      subtitlePreferences: subtitlePreferences ?? this.subtitlePreferences,
      enableMiniPlayer: enableMiniPlayer ?? this.enableMiniPlayer,
      useExternalPlayer: useExternalPlayer ?? this.useExternalPlayer,
      externalPlayerPath: clearExternalPlayerPath
          ? null
          : (externalPlayerPath ?? this.externalPlayerPath),
    );
  }

  Map<String, dynamic> toJson() => {
    'maxStreamingBitrate': maxStreamingBitrate.name,
    'hardwareDecodingMode': hardwareDecodingMode.name,
    'subtitlePreferences': subtitlePreferences.toJson(),
    'enableMiniPlayer': enableMiniPlayer,
    'useExternalPlayer': useExternalPlayer,
    'externalPlayerPath': externalPlayerPath,
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
      enableMiniPlayer: json['enableMiniPlayer'] as bool? ?? true,
      useExternalPlayer: json['useExternalPlayer'] as bool? ?? false,
      externalPlayerPath: json['externalPlayerPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaybackSettings &&
        other.maxStreamingBitrate == maxStreamingBitrate &&
        other.hardwareDecodingMode == hardwareDecodingMode &&
        other.subtitlePreferences == subtitlePreferences &&
        other.enableMiniPlayer == enableMiniPlayer &&
        other.useExternalPlayer == useExternalPlayer &&
        other.externalPlayerPath == externalPlayerPath;
  }

  @override
  int get hashCode => Object.hash(
    maxStreamingBitrate,
    hardwareDecodingMode,
    subtitlePreferences,
    enableMiniPlayer,
    useExternalPlayer,
    externalPlayerPath,
  );
}
