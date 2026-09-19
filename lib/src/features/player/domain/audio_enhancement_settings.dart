enum AudioEnhancementMode {
  off('关闭', ''),
  nightMode('夜间对话增强', 'lavfi=[dynaudnorm=f=75:g=15:p=0.95]'),
  vocalBoost('人声突出', 'lavfi=[equalizer=f=1000:width_type=h:w=200:g=3]'),
  bassBoost('极客低音', 'lavfi=[equalizer=f=60:width_type=h:w=100:g=5]');

  const AudioEnhancementMode(this.label, this.mpvFilter);
  final String label;
  final String mpvFilter;
}

enum ToneMappingAlgorithm {
  auto('自动', 'mobius'),
  mobius('Mobius 算法', 'mobius'),
  hable('Hable 算法', 'hable'),
  reinhard('Reinhard 算法', 'reinhard'),
  spline('Spline 算法', 'spline'),
  bt2390('BT.2390 (HDR标准)', 'bt.2390');

  const ToneMappingAlgorithm(this.label, this.mpvValue);
  final String label;
  final String mpvValue;
}
