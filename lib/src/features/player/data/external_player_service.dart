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

    // 1. Check common PotPlayer and VLC locations across drive letters
    final driveLetters = ['C', 'D', 'E', 'F', 'G', 'H'];
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

    // 2. Query Windows Registry (App Paths and URL Protocol Associations)
    final regKeys = [
      r'HKCR\potplayer\shell\open\command',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayerMini64.exe',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayer64.exe',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayerMini64.exe',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayer64.exe',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\vlc.exe',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\vlc.exe',
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
                final lower = path.toLowerCase();
                final exeIdx = lower.indexOf('.exe');
                if (exeIdx != -1) {
                  path = path.substring(0, exeIdx + 4);
                }
                if (path.startsWith('"')) {
                  path = path.substring(1);
                }
                if (path.endsWith('"')) {
                  path = path.substring(0, path.length - 1);
                }
                path = path.trim();
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
  Future<String> resolvePlayableUrl(PlaybackPlan plan) async {
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

    // Only attach Emby/Jellyfin token if this is a server stream (has MediaSourceId, Videos/Items path, or server query params)
    final lowerPath = uri.path.toLowerCase();
    final queryKeysLower = uri.queryParameters.keys.map((k) => k.toLowerCase()).toSet();
    final isServerStream = lowerPath.contains('/videos/') ||
        lowerPath.contains('/items/') ||
        queryKeysLower.contains('mediasourceid') ||
        queryKeysLower.contains('api_key') ||
        queryKeysLower.contains('x-emby-token') ||
        queryKeysLower.contains('token');

    if (isServerStream) {
      final token = plan.httpHeaders['X-Emby-Token'] ??
          plan.httpHeaders['X-MediaBrowser-Token'] ??
          plan.httpHeaders['api_key'] ??
          uri.queryParameters['X-Emby-Token'] ??
          uri.queryParameters['X-MediaBrowser-Token'] ??
          uri.queryParameters['api_key'] ??
          uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        final params = Map<String, String>.from(uri.queryParameters);
        params.putIfAbsent('api_key', () => token);
        params.putIfAbsent('X-Emby-Token', () => token);
        params.putIfAbsent('X-MediaBrowser-Token', () => token);
        params.putIfAbsent('token', () => token);
        uri = uri.replace(queryParameters: params);
      }
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

  /// Builds command-line arguments for PotPlayer.
  /// Switches must be passed BEFORE the target URL.
  List<String> buildPotPlayerArgs({
    required String targetUrl,
    Duration? seekPosition,
    String? title,
    Map<String, String> httpHeaders = const {},
    Uri? streamUri,
    Uri? subtitleUri,
  }) {
    final args = <String>[];

    // 1. Start position / seek
    if (seekPosition != null && seekPosition > Duration.zero) {
      args.add('/seek=${formatHms(seekPosition)}');
    }

    // Note: PotPlayer does not support a /title= switch. Any unrecognized switch
    // is treated as an input media file by PotPlayer, causing render/pin failures.

    // 2. User agent
    final userAgent = httpHeaders['User-Agent'];
    if (userAgent != null && userAgent.isNotEmpty) {
      args.add('/user_agent=$userAgent');
    }

    // 4. Referer
    if (streamUri != null &&
        (streamUri.scheme == 'http' || streamUri.scheme == 'https')) {
      final portSuffix = streamUri.hasPort ? ':${streamUri.port}' : '';
      args.add('/referer=${streamUri.scheme}://${streamUri.host}$portSuffix/');
    }

    // 5. Headers (separated by CRLF; token formatted without internal quotes)
    // Only send server auth headers if targetUrl is a server stream
    final streamLowerPath = streamUri?.path.toLowerCase() ?? '';
    final streamQueryKeysLower = streamUri?.queryParameters.keys.map((k) => k.toLowerCase()).toSet() ?? const {};
    final isServerUrl = streamUri != null &&
        (streamLowerPath.contains('/videos/') ||
            streamLowerPath.contains('/items/') ||
            streamQueryKeysLower.contains('mediasourceid') ||
            streamQueryKeysLower.contains('api_key') ||
            streamQueryKeysLower.contains('x-emby-token') ||
            streamQueryKeysLower.contains('token'));

    if (isServerUrl) {
      final token = httpHeaders['X-Emby-Token'] ??
          httpHeaders['X-MediaBrowser-Token'] ??
          httpHeaders['api_key'];
      final headerLines = <String>[];
      if (token != null && token.isNotEmpty) {
        headerLines.add('X-Emby-Token: $token');
        headerLines.add('X-MediaBrowser-Token: $token');
        headerLines.add('Authorization: MediaBrowser Token=$token');
      }
      if (headerLines.isNotEmpty) {
        args.add('/headers=${headerLines.join('\r\n')}');
      }
    }

    // 6. External subtitle file or URL
    if (subtitleUri != null) {
      final subPath = subtitleUri.isScheme('file')
          ? subtitleUri.toFilePath()
          : subtitleUri.toString();
      args.add('/sub=$subPath');
    }

    // 7. Target media URL or file path MUST come last
    args.add(targetUrl);

    return args;
  }

  /// Builds command-line arguments for VLC Media Player.
  List<String> buildVlcArgs({
    required String targetUrl,
    Duration? seekPosition,
    String? title,
    Map<String, String> httpHeaders = const {},
  }) {
    final args = <String>[];
    if (seekPosition != null && seekPosition > Duration.zero) {
      args.add('--start-time=${seekPosition.inSeconds}');
    }
    if (title != null && title.trim().isNotEmpty) {
      args.add('--meta-title=${title.trim()}');
    }
    args.add(targetUrl);
    return args;
  }

  /// Launches an external player with the given playback plan.
  Future<bool> launch(
    PlaybackPlan plan, {
    String? executablePath,
    Duration? seekPosition,
    String? title,
  }) async {
    // Resolve target path or stream URL (with STRM & token resolution)
    final targetUrl = await resolvePlayableUrl(plan);

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

      final List<String> args;
      if (isPotPlayer) {
        final externalSub = plan.subtitleTracks
            .where((t) => t.isExternal && t.deliveryUri != null)
            .firstOrNull;
        args = buildPotPlayerArgs(
          targetUrl: targetUrl,
          seekPosition: position,
          title: title,
          httpHeaders: plan.httpHeaders,
          streamUri: plan.streamUri,
          subtitleUri: externalSub?.deliveryUri,
        );
      } else if (isVlc) {
        args = buildVlcArgs(
          targetUrl: targetUrl,
          seekPosition: position,
          title: title,
          httpHeaders: plan.httpHeaders,
        );
      } else {
        args = [targetUrl];
      }

      try {
        await Process.start(exe, args, mode: ProcessStartMode.detached);
        return true;
      } on Object {
        // Fallback to protocol launch
      }
    }

    // Fallback: Launch via Windows URL scheme or shell open (using PowerShell to avoid & splitting)
    if (Platform.isWindows) {
      try {
        final potScheme = 'potplayer://$targetUrl';
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-Command', 'Start-Process', potScheme],
        );
        if (result.exitCode == 0) return true;
      } on Object {
        // Continue to generic open
      }

      try {
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-Command', 'Start-Process', targetUrl],
        );
        return result.exitCode == 0;
      } on Object {
        return false;
      }
    }

    return false;
  }
}
