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

class PlaybackSettings {
  const PlaybackSettings({this.maxStreamingBitrate = PlaybackBitrate.original});

  final PlaybackBitrate maxStreamingBitrate;

  PlaybackSettings copyWith({PlaybackBitrate? maxStreamingBitrate}) {
    return PlaybackSettings(
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
    );
  }

  Map<String, dynamic> toJson() => {
    'maxStreamingBitrate': maxStreamingBitrate.name,
  };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      maxStreamingBitrate: PlaybackBitrate.fromName(
        json['maxStreamingBitrate'],
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaybackSettings &&
        other.maxStreamingBitrate == maxStreamingBitrate;
  }

  @override
  int get hashCode => maxStreamingBitrate.hashCode;
}
