import 'dart:convert';
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

  /// Resolves the actual playable URL, parsing .strm files and injecting auth tokens.
  Future<String> _resolvePlayableUrl(PlaybackPlan plan) async {
    if (plan.streamUri.isScheme('file')) {
      final filePath = plan.streamUri.toFilePath();
      if (filePath.toLowerCase().endsWith('.strm') && File(filePath).existsSync()) {
        try {
          final lines = await File(filePath).readAsLines();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            if (trimmed.startsWith('http://') ||
                trimmed.startsWith('https://') ||
                trimmed.startsWith('rtmp://') ||
                trimmed.startsWith('rtsp://') ||
                trimmed.startsWith('file://')) {
              return trimmed;
            }
          }
        } catch (_) {}
      }
      return filePath;
    }

    var uri = plan.streamUri;

    // Attach Emby/Jellyfin token if missing from query params
    final token = plan.httpHeaders['X-Emby-Token'] ??
        plan.httpHeaders['X-MediaBrowser-Token'] ??
        plan.httpHeaders['api_key'];
    if (token != null &&
        !uri.queryParameters.containsKey('api_key') &&
        !uri.queryParameters.containsKey('X-Emby-Token')) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'api_key': token,
        },
      );
    }

    var targetUrl = uri.toString();

    // Check if the remote URL ends in .strm
    final cleanPath = uri.path.toLowerCase();
    if (cleanPath.endsWith('.strm') &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final request = await client.getUrl(uri);
        plan.httpHeaders.forEach((k, v) {
          request.headers.set(k, v);
        });
        final response =
            await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          for (final line in body.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            if (trimmed.startsWith('http://') ||
                trimmed.startsWith('https://') ||
                trimmed.startsWith('rtmp://') ||
                trimmed.startsWith('rtsp://')) {
              targetUrl = trimmed;
              break;
            }
          }
        }
      } catch (_) {}
    }

    return targetUrl;
  }

  /// Launches an external player with the given playback plan.
  Future<bool> launch(
    PlaybackPlan plan, {
    String? executablePath,
    Duration? seekPosition,
    String? title,
  }) async {
    // Resolve target path or stream URL (with STRM & token resolution)
    final targetUrl = await _resolvePlayableUrl(plan);

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
        final userAgent = plan.httpHeaders['User-Agent'];
        if (userAgent != null && userAgent.isNotEmpty) {
          args.add('/user_agent=$userAgent');
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
