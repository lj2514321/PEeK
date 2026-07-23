import 'dart:io';

import 'package:embyplayer/src/features/player/data/windows_media_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('peek/windows_media_session_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => <String, Object?>{'available': true, 'smtc': true},
        'bindVolume' => <String, Object?>{'level': 64.0, 'muted': false},
        _ => null,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'synchronizes metadata, playback, timeline and session volume',
    () async {
      final session = WindowsMediaSession(
        channel: channel,
        isWindows: () => true,
      );

      expect(
        await session.initialize(
          onCommand: (_) {},
          onVolumeChanged: (_) {},
          onVolumeSessionDisconnected: () {},
        ),
        isTrue,
      );
      await session.updateMetadata(
        const SystemMediaMetadata(title: '示例电影', subtitle: '2026'),
      );
      await session.updatePlayback(
        state: SystemMediaPlaybackState.playing,
        canPrevious: true,
        canNext: false,
      );
      await session.updateTimeline(
        position: const Duration(minutes: 12),
        duration: const Duration(hours: 2),
        playbackRate: 1.25,
      );
      final volume = await session.bindVolume();
      await session.setVolume(38);
      await session.dispose();

      expect(volume?.level, 64);
      expect(volume?.muted, isFalse);
      expect(calls.map((call) => call.method), [
        'initialize',
        'updateMetadata',
        'updatePlayback',
        'updateTimeline',
        'bindVolume',
        'setVolume',
        'dispose',
      ]);
      expect(
        calls.firstWhere((call) => call.method == 'updatePlayback').arguments,
        {'state': 'playing', 'canPrevious': true, 'canNext': false},
      );
      expect(
        calls.firstWhere((call) => call.method == 'updateTimeline').arguments,
        {
          'positionMs': const Duration(minutes: 12).inMilliseconds,
          'durationMs': const Duration(hours: 2).inMilliseconds,
          'playbackRate': 1.25,
        },
      );
    },
  );

  test('maps native commands and audio-session events', () async {
    final commands = <SystemMediaCommand>[];
    final volumes = <SystemAudioVolume>[];
    var disconnected = false;
    final session = WindowsMediaSession(
      channel: channel,
      isWindows: () => true,
    );
    await session.initialize(
      onCommand: commands.add,
      onVolumeChanged: volumes.add,
      onVolumeSessionDisconnected: () => disconnected = true,
    );

    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('command', {'type': 'seek', 'positionMs': 42000}),
      ),
      null,
    );
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('command', {'type': 'next'})),
      null,
    );
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('volumeChanged', {'level': 72.0, 'muted': true}),
      ),
      null,
    );
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('volumeSessionDisconnected', {})),
      null,
    );

    expect(commands.map((command) => command.type), [
      SystemMediaCommandType.seek,
      SystemMediaCommandType.next,
    ]);
    expect(commands.first.position, const Duration(seconds: 42));
    expect(volumes.single.level, 72);
    expect(volumes.single.effectiveLevel, 0);
    expect(disconnected, isTrue);
  });

  test('is a no-op outside Windows', () async {
    final session = WindowsMediaSession(
      channel: channel,
      isWindows: () => false,
    );

    expect(
      await session.initialize(
        onCommand: (_) {},
        onVolumeChanged: (_) {},
        onVolumeSessionDisconnected: () {},
      ),
      isFalse,
    );
    expect(calls, isEmpty);
  });

  test('registers the native bridge and required Windows libraries', () {
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final bridge = File(
      'windows/runner/windows_media_session.cpp',
    ).readAsStringSync();

    expect(cmake, contains('"windows_media_session.cpp"'));
    expect(cmake, contains('"windowsapp.lib"'));
    expect(window, contains('WindowsMediaSessionBridge::Create'));
    expect(bridge, contains('ISystemMediaTransportControlsInterop'));
    expect(bridge, contains('IAudioSessionEvents'));
    expect(bridge, contains('ISimpleAudioVolume'));
  });
}
