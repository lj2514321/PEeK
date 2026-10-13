class AudioEqualizerBand {
  const AudioEqualizerBand({
    required this.frequencyHz,
    required this.label,
    required this.gainDb,
  });

  final int frequencyHz;
  final String label;
  final double gainDb;

  AudioEqualizerBand copyWith({double? gainDb}) {
    return AudioEqualizerBand(
      frequencyHz: frequencyHz,
      label: label,
      gainDb: (gainDb ?? this.gainDb).clamp(-12.0, 12.0),
    );
  }
}

enum AudioEqualizerPreset {
  flat(
    id: 'flat',
    label: '标准 (Flat)',
    gains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  ),
  bassBoost(
    id: 'bass',
    label: '澎湃重低音',
    gains: [6.0, 5.0, 3.5, 1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  ),
  vocalBoost(
    id: 'vocal',
    label: '清晰人声对白',
    gains: [-1.5, -1.0, 0.0, 2.0, 4.5, 5.0, 3.0, 1.0, 0.0, -1.0],
  ),
  cinema(
    id: 'cinema',
    label: '沉浸影院 (V型)',
    gains: [5.0, 4.0, 2.0, 0.0, -1.5, 0.0, 2.0, 3.5, 4.5, 5.0],
  ),
  rock(
    id: 'rock',
    label: '摇滚动感',
    gains: [4.5, 3.5, 2.0, 0.5, -1.0, 0.0, 1.5, 3.0, 4.0, 4.5],
  ),
  classical(
    id: 'classical',
    label: '古典柔和',
    gains: [3.0, 2.5, 2.0, 1.0, -0.5, 0.0, 1.0, 2.0, 3.0, 3.5],
  ),
  custom(
    id: 'custom',
    label: '自定义',
    gains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  );

  const AudioEqualizerPreset({
    required this.id,
    required this.label,
    required this.gains,
  });

  final String id;
  final String label;
  final List<double> gains;
}

class AudioEqualizerSettings {
  const AudioEqualizerSettings({
    required this.enabled,
    required this.bands,
    required this.activePreset,
  });

  factory AudioEqualizerSettings.initial() {
    const freqs = [
      (31, '31Hz'),
      (62, '62Hz'),
      (125, '125Hz'),
      (250, '250Hz'),
      (500, '500Hz'),
      (1000, '1kHz'),
      (2000, '2kHz'),
      (4000, '4kHz'),
      (8000, '8kHz'),
      (16000, '16kHz'),
    ];
    return AudioEqualizerSettings(
      enabled: false,
      activePreset: AudioEqualizerPreset.flat,
      bands: freqs
          .map(
            (f) =>
                AudioEqualizerBand(frequencyHz: f.$1, label: f.$2, gainDb: 0.0),
          )
          .toList(growable: false),
    );
  }

  final bool enabled;
  final List<AudioEqualizerBand> bands;
  final AudioEqualizerPreset activePreset;

  AudioEqualizerSettings copyWith({
    bool? enabled,
    List<AudioEqualizerBand>? bands,
    AudioEqualizerPreset? activePreset,
  }) {
    return AudioEqualizerSettings(
      enabled: enabled ?? this.enabled,
      bands: bands ?? this.bands,
      activePreset: activePreset ?? this.activePreset,
    );
  }

  AudioEqualizerSettings applyPreset(AudioEqualizerPreset preset) {
    final newBands = <AudioEqualizerBand>[];
    for (var i = 0; i < bands.length; i++) {
      final gain = i < preset.gains.length ? preset.gains[i] : 0.0;
      newBands.add(bands[i].copyWith(gainDb: gain));
    }
    return copyWith(
      enabled: preset != AudioEqualizerPreset.flat,
      bands: newBands,
      activePreset: preset,
    );
  }

  AudioEqualizerSettings updateBand(int index, double gainDb) {
    if (index < 0 || index >= bands.length) return this;
    final updated = List<AudioEqualizerBand>.from(bands);
    updated[index] = updated[index].copyWith(gainDb: gainDb);
    return copyWith(
      enabled: true,
      bands: updated,
      activePreset: AudioEqualizerPreset.custom,
    );
  }

  String toMpvFilter() {
    if (!enabled) return '';
    final filters = <String>[];
    for (final band in bands) {
      if (band.gainDb.abs() > 0.05) {
        filters.add(
          'equalizer=f=${band.frequencyHz}:width_type=o:w=1:g=${band.gainDb.toStringAsFixed(1)}',
        );
      }
    }
    if (filters.isEmpty) return '';
    return 'lavfi=[${filters.join(',')}]';
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'preset': activePreset.id,
      'gains': bands.map((b) => b.gainDb).toList(),
    };
  }

  factory AudioEqualizerSettings.fromJson(Map<String, dynamic> json) {
    final base = AudioEqualizerSettings.initial();
    final enabled = json['enabled'] == true;
    final presetId = json['preset']?.toString();
    final gainsList = json['gains'];

    var preset = AudioEqualizerPreset.flat;
    for (final p in AudioEqualizerPreset.values) {
      if (p.id == presetId) {
        preset = p;
        break;
      }
    }

    if (gainsList is List && gainsList.length == base.bands.length) {
      final newBands = <AudioEqualizerBand>[];
      for (var i = 0; i < base.bands.length; i++) {
        final g = gainsList[i];
        final val = g is num ? g.toDouble() : 0.0;
        newBands.add(base.bands[i].copyWith(gainDb: val));
      }
      return AudioEqualizerSettings(
        enabled: enabled,
        bands: newBands,
        activePreset: preset,
      );
    }

    return base.applyPreset(preset).copyWith(enabled: enabled);
  }
}
