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

class PlaybackSettings {
  const PlaybackSettings({
    this.maxStreamingBitrate = PlaybackBitrate.original,
    this.hardwareDecodingMode = HardwareDecodingMode.automatic,
  });

  final PlaybackBitrate maxStreamingBitrate;
  final HardwareDecodingMode hardwareDecodingMode;

  PlaybackSettings copyWith({
    PlaybackBitrate? maxStreamingBitrate,
    HardwareDecodingMode? hardwareDecodingMode,
  }) {
    return PlaybackSettings(
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
      hardwareDecodingMode: hardwareDecodingMode ?? this.hardwareDecodingMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'maxStreamingBitrate': maxStreamingBitrate.name,
    'hardwareDecodingMode': hardwareDecodingMode.name,
  };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      maxStreamingBitrate: PlaybackBitrate.fromName(
        json['maxStreamingBitrate'],
      ),
      hardwareDecodingMode: HardwareDecodingMode.fromName(
        json['hardwareDecodingMode'],
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaybackSettings &&
        other.maxStreamingBitrate == maxStreamingBitrate &&
        other.hardwareDecodingMode == hardwareDecodingMode;
  }

  @override
  int get hashCode => Object.hash(maxStreamingBitrate, hardwareDecodingMode);
}
