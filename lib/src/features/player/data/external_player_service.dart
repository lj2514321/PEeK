import 'dart:io';

import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final externalPlayerServiceProvider = Provider<ExternalPlayerService>((ref) {
  return const ExternalPlayerService();
});

class ExternalPlayerDescriptor {
  const ExternalPlayerDescriptor({
    required this.name,
    required this.executablePath,
    this.isDefault = false,
  });

  final String name;
  final String executablePath;
  final bool isDefault;
}

class ExternalPlayerService {
  const ExternalPlayerService();

  /// Detects installed external players on Windows (PotPlayer, VLC, etc.).
  Future<ExternalPlayerDescriptor?> detectExternalPlayer() async {
    if (!Platform.isWindows) return null;

    // 1. Check common PotPlayer locations across drive letters
    final driveLetters = ['C', 'D', 'E', 'F', 'G'];
    final commonSubpaths = [
      r'Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
      r'Program Files\DAUM\PotPlayer\PotPlayer64.exe',
      r'Program Files (x86)\DAUM\PotPlayer\PotPlayerMini.exe',
      r'Program Files (x86)\DAUM\PotPlayer\PotPlayer.exe',
      r'Program Files\VideoLAN\VLC\vlc.exe',
      r'Program Files (x86)\VideoLAN\VLC\vlc.exe',
    ];

    for (final drive in driveLetters) {
      for (final sub in commonSubpaths) {
        final path = '$drive:\\$sub';
        if (File(path).existsSync()) {
          final isPot = sub.toLowerCase().contains('potplayer');
          return ExternalPlayerDescriptor(
            name: isPot ? 'PotPlayer' : 'VLC Media Player',
            executablePath: path,
            isDefault: true,
          );
        }
      }
    }

    // 2. Query Windows Registry App Paths via reg query
    final regKeys = [
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayerMini64.exe',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayer64.exe',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\vlc.exe',
    ];

    for (final key in regKeys) {
      try {
        final result = await Process.run('reg', ['query', key, '/ve']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('REG_SZ')) {
              final parts = line.split('REG_SZ');
              if (parts.length >= 2) {
                var path = parts[1].trim();
                if (path.startsWith('"') && path.endsWith('"')) {
                  path = path.substring(1, path.length - 1);
                }
                if (path.isNotEmpty && File(path).existsSync()) {
                  final isPot = path.toLowerCase().contains('potplayer');
                  return ExternalPlayerDescriptor(
                    name: isPot ? 'PotPlayer' : 'VLC Media Player',
                    executablePath: path,
                    isDefault: true,
                  );
                }
              }
            }
          }
        }
      } on Object {
        // Ignore registry query failures
      }
    }

    return null;
  }

  /// Formats duration to HH:MM:SS for player seek arguments.
  static String formatHms(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Launches an external player with the given playback plan.
  Future<bool> launch(
    PlaybackPlan plan, {
    String? executablePath,
    Duration? seekPosition,
    String? title,
  }) async {
    // Resolve target path or stream URL
    String targetUrl;
    if (plan.streamUri.isScheme('file')) {
      targetUrl = plan.streamUri.toFilePath();
    } else {
      targetUrl = plan.streamUri.toString();
    }

    // Resolve executable
    String? exe = executablePath;
    if (exe == null || exe.trim().isEmpty || !File(exe).existsSync()) {
      final detected = await detectExternalPlayer();
      exe = detected?.executablePath;
    }

    final position = seekPosition ?? plan.startPosition;

    if (exe != null && File(exe).existsSync()) {
      final isPotPlayer = exe.toLowerCase().contains('potplayer');
      final isVlc = exe.toLowerCase().contains('vlc');

      final args = <String>[targetUrl];

      if (isPotPlayer) {
        if (position > Duration.zero) {
          args.add('/seek=${formatHms(position)}');
        }
        if (title != null && title.trim().isNotEmpty) {
          args.add('/title=$title');
        }
        // Attach external subtitle if present in plan
        final externalSub = plan.subtitleTracks
            .where((t) => t.isExternal && t.deliveryUri != null)
            .firstOrNull;
        if (externalSub?.deliveryUri != null) {
          final subUri = externalSub!.deliveryUri!;
          final subPath = subUri.isScheme('file')
              ? subUri.toFilePath()
              : subUri.toString();
          args.add('/sub=$subPath');
        }
      } else if (isVlc) {
        if (position > Duration.zero) {
          args.add('--start-time=${position.inSeconds}');
        }
      }

      try {
        await Process.start(exe, args, mode: ProcessStartMode.detached);
        return true;
      } on Object {
        // Fallback to protocol launch
      }
    }

    // Fallback: Launch via Windows URL scheme or shell open
    if (Platform.isWindows) {
      try {
        final potScheme = 'potplayer://$targetUrl';
        final result = await Process.run('cmd', ['/c', 'start', '""', potScheme]);
        if (result.exitCode == 0) return true;
      } on Object {
        // Continue to generic open
      }

      try {
        final result = await Process.run('cmd', ['/c', 'start', '""', targetUrl]);
        return result.exitCode == 0;
      } on Object {
        return false;
      }
    }

    return false;
  }
}
