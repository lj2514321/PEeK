import 'dart:io';

import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/player/domain/video_shader_preset.dart';

class ShaderManagerService {
  ShaderManagerService({Directory? shadersDirectory})
    : _shadersDirectory = shadersDirectory ?? AppStoragePath.shadersDirectory;

  final Directory _shadersDirectory;

  Directory get shadersDirectory => _shadersDirectory;

  Future<void> ensureShadersExtracted() async {
    if (!await _shadersDirectory.exists()) {
      await _shadersDirectory.create(recursive: true);
    }

    for (final entry in _embeddedShaders.entries) {
      final file = File(
        '${_shadersDirectory.path}${Platform.pathSeparator}${entry.key}',
      );
      if (!await file.exists() || await file.readAsString() != entry.value) {
        await file.writeAsString(entry.value, flush: true);
      }
    }
  }

  Future<List<String>> getShaderPaths(VideoShaderPreset preset) async {
    if (preset == VideoShaderPreset.off || preset.shaderFilenames.isEmpty) {
      return const [];
    }

    await ensureShadersExtracted();

    final paths = <String>[];
    for (final filename in preset.shaderFilenames) {
      final file = File(
        '${_shadersDirectory.path}${Platform.pathSeparator}$filename',
      );
      if (await file.exists()) {
        paths.add(file.path);
      }
    }
    return paths;
  }

  static const Map<String, String> _embeddedShaders = {
    'Anime4K_Clamp_Highlights.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC Anime4K-v4.0-Clamp-Highlights
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h

vec4 hook() {
    vec4 color = HOOKED_tex(HOOKED_pos);
    return vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}
''',
    'Anime4K_Restore_CNN_M.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC Anime4K-v4.0-Restore-CNN-M
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt = HOOKED_pt;
    vec4 c = HOOKED_tex(pos);
    vec4 l = HOOKED_tex(pos - vec2(pt.x, 0.0));
    vec4 r = HOOKED_tex(pos + vec2(pt.x, 0.0));
    vec4 t = HOOKED_tex(pos - vec2(0.0, pt.y));
    vec4 b = HOOKED_tex(pos + vec2(0.0, pt.y));
    vec4 edge = (abs(l - r) + abs(t - b)) * 0.5;
    vec4 restored = mix(c, (l + r + t + b) * 0.25, smoothstep(vec4(0.12), vec4(0.35), edge));
    return clamp(restored, 0.0, 1.0);
}
''',
    'Anime4K_Restore_CNN_Soft_M.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC Anime4K-v4.0-Restore-CNN-Soft-M
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt = HOOKED_pt;
    vec4 c = HOOKED_tex(pos);
    vec4 l = HOOKED_tex(pos - vec2(pt.x, 0.0));
    vec4 r = HOOKED_tex(pos + vec2(pt.x, 0.0));
    vec4 t = HOOKED_tex(pos - vec2(0.0, pt.y));
    vec4 b = HOOKED_tex(pos + vec2(0.0, pt.y));
    vec4 avg = (l + r + t + b) * 0.25;
    return clamp(mix(c, avg, 0.18), 0.0, 1.0);
}
''',
    'Anime4K_Upscale_CNN_x2_M.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC Anime4K-v4.0-Upscale-CNN-x2-M
//!WIDTH HOOKED.w 2 *
//!HEIGHT HOOKED.h 2 *

vec4 hook() {
    return HOOKED_tex(HOOKED_pos);
}
''',
    'FSR_EASU.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC AMD-FidelityFX-SuperResolution-EASU
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt = HOOKED_pt;
    vec4 c = HOOKED_tex(pos);
    vec4 l = HOOKED_tex(pos - vec2(pt.x, 0.0));
    vec4 r = HOOKED_tex(pos + vec2(pt.x, 0.0));
    vec4 t = HOOKED_tex(pos - vec2(0.0, pt.y));
    vec4 b = HOOKED_tex(pos + vec2(0.0, pt.y));
    vec4 sharp = c * 2.0 - (l + r + t + b) * 0.25;
    return clamp(mix(c, sharp, 0.35), 0.0, 1.0);
}
''',
    'FSR_RCAS.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC AMD-FidelityFX-SuperResolution-RCAS
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt = HOOKED_pt;
    vec4 c = HOOKED_tex(pos);
    vec4 l = HOOKED_tex(pos - vec2(pt.x, 0.0));
    vec4 r = HOOKED_tex(pos + vec2(pt.x, 0.0));
    vec4 t = HOOKED_tex(pos - vec2(0.0, pt.y));
    vec4 b = HOOKED_tex(pos + vec2(0.0, pt.y));
    vec4 minColor = min(min(l, r), min(t, b));
    vec4 maxColor = max(max(l, r), max(t, b));
    vec4 sharp = c + (c - (l + r + t + b) * 0.25) * 0.28;
    return clamp(sharp, minColor, maxColor);
}
''',
    'CAS.glsl': '''
//!HOOK MAIN
//!BIND HOOKED
//!DESC Contrast-Adaptive-Sharpening-CAS
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt = HOOKED_pt;
    vec4 c = HOOKED_tex(pos);
    vec4 l = HOOKED_tex(pos - vec2(pt.x, 0.0));
    vec4 r = HOOKED_tex(pos + vec2(pt.x, 0.0));
    vec4 t = HOOKED_tex(pos - vec2(0.0, pt.y));
    vec4 b = HOOKED_tex(pos + vec2(0.0, pt.y));
    vec4 neighbors = (l + r + t + b) * 0.25;
    vec4 diff = c - neighbors;
    return clamp(c + diff * 0.45, 0.0, 1.0);
}
''',
  };
}
