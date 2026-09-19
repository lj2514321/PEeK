enum VideoShaderPreset {
  off(
    id: 'off',
    label: '原画直出',
    description: '原生色彩与分辨率渲染，无额外 GPU 占用',
    gpuLoad: '无消耗',
    shaderFilenames: [],
  ),
  anime4kModeA(
    id: 'anime4k_a',
    label: 'Anime4K 极致重构 (Mode A)',
    description: '针对动漫与老番：AI 级边缘线条抗锯齿、伪影消除与超采样',
    gpuLoad: '高负载 (推荐独立显卡)',
    shaderFilenames: ['Anime4K_Restore_CNN_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl'],
  ),
  anime4kModeB(
    id: 'anime4k_b',
    label: 'Anime4K 平衡增强 (Mode B)',
    description: '轻量级动漫纹理细化与抗锯齿，适合轻薄本核显流畅运行',
    gpuLoad: '中低负载 (适合核显)',
    shaderFilenames: ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl'],
  ),
  fsr(
    id: 'fsr',
    label: 'AMD FidelityFX FSR 超分',
    description: '高保真边缘超分辨率重建，适合实拍电影与电视剧画质提拔',
    gpuLoad: '中等负载',
    shaderFilenames: ['FSR_EASU.glsl', 'FSR_RCAS.glsl'],
  ),
  cas(
    id: 'cas',
    label: 'CAS 对比度自适应锐化',
    description: '强化高码率原盘细节质感，抑制光晕瑕疵，适合 4K 实拍',
    gpuLoad: '极低负载',
    shaderFilenames: ['CAS.glsl'],
  );

  const VideoShaderPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.gpuLoad,
    required this.shaderFilenames,
  });

  final String id;
  final String label;
  final String description;
  final String gpuLoad;
  final List<String> shaderFilenames;

  bool get isEnabled => this != VideoShaderPreset.off;

  static VideoShaderPreset fromId(String? id) {
    for (final preset in values) {
      if (preset.id == id) return preset;
    }
    return VideoShaderPreset.off;
  }
}
