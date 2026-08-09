enum AudioEnhancementMode {
  off('关闭', ''),
  nightMode('夜间对话增强', 'lavfi=[dynaudnorm=f=75:g=15:p=0.95]'),
  vocalBoost('人声突出', 'equalizer=g=3:f=1000:w=200'),
  bassBoost('极客低音', 'equalizer=g=5:f=60:w=100');

  const AudioEnhancementMode(this.label, this.mpvFilter);
  final String label;
  final String mpvFilter;
}

enum ToneMappingAlgorithm {
  auto('自动', 'auto'),
  mobius('Mobius 算法', 'mobius'),
  hable('Hable 算法', 'hable'),
  reinhard('Reinhard 算法', 'reinhard');

  const ToneMappingAlgorithm(this.label, this.mpvValue);
  final String label;
  final String mpvValue;
}
