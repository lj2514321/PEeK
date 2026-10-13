import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/local_library/domain/local_media_library.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:embyplayer/src/features/servers/presentation/server_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(375, 812), Size(1280, 800)]) {
    testWidgets('lays out server accounts at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(state: _state()));
      await tester.pumpAndSettle();

      expect(find.text('服务器与账户'), findsOneWidget);
      expect(find.text('正在使用'), findsOneWidget);
      expect(find.text('客厅服务器'), findsWidgets);
      expect(find.text('书房服务器'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switches to another signed-in server', (tester) async {
    String? switchedProfileId;
    final state = _state();

    await tester.pumpWidget(
      _app(
        state: state,
        onSwitch: (entry) async => switchedProfileId = entry.profile.id,
      ),
    );
    await tester.pumpAndSettle();

    final study = state.accounts[1];
    final switchButton = find.byKey(ValueKey('switch-${study.profile.id}'));
    await tester.ensureVisible(switchButton);
    await tester.pumpAndSettle();
    await tester.tap(switchButton);
    await tester.pump();

    expect(switchedProfileId, study.profile.id);
  });

  testWidgets('offers a login action for a signed-out server', (tester) async {
    String? loginProfileId;
    final state = _state();

    await tester.pumpWidget(
      _app(
        state: state,
        onLogin: (entry) async => loginProfileId = entry.profile.id,
      ),
    );
    await tester.pumpAndSettle();

    final bedroom = state.accounts[2];
    final loginButton = find.byKey(ValueKey('login-${bedroom.profile.id}'));
    await tester.ensureVisible(loginButton);
    await tester.pumpAndSettle();
    await tester.tap(loginButton);
    await tester.pump();

    expect(loginProfileId, bedroom.profile.id);
  });

  testWidgets('selects a maximum streaming bitrate', (tester) async {
    PlaybackBitrate? selected;
    await tester.pumpWidget(
      _app(
        state: _state(),
        playbackSettings: const PlaybackSettings(
          maxStreamingBitrate: PlaybackBitrate.mbps20,
        ),
        onPlaybackBitrateChanged: (value) => selected = value,
      ),
    );
    await tester.pumpAndSettle();

    final option = find.byKey(const ValueKey('playback-bitrate-mbps10'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();

    expect(selected, PlaybackBitrate.mbps10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a hardware decoding mode', (tester) async {
    HardwareDecodingMode? selected;
    await tester.pumpWidget(
      _app(
        state: _state(),
        onHardwareDecodingModeChanged: (value) => selected = value,
      ),
    );
    await tester.pumpAndSettle();

    final option = find.byKey(const ValueKey('hardware-decoding-software'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();

    expect(selected, HardwareDecodingMode.software);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a long press playback speed', (tester) async {
    double? selected;
    await tester.pumpWidget(
      _app(
        state: _state(),
        playbackSettings: const PlaybackSettings(longPressSpeed: 2.0),
        onLongPressSpeedChanged: (value) => selected = value,
      ),
    );
    await tester.pumpAndSettle();

    final option = find.byKey(const ValueKey('long-press-speed-2.5'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();

    expect(selected, 2.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows and removes a saved local media library', (tester) async {
    final library = LocalMediaLibrary(
      id: 'local-library',
      name: 'Local Videos',
      path: r'C:\Media',
      addedAt: DateTime(2026, 8, 4),
    );
    LocalMediaLibrary? removed;
    await tester.pumpWidget(
      _app(
        state: _state(),
        localLibraries: [library],
        onRemoveLocalLibrary: (value) async => removed = value,
      ),
    );
    await tester.pumpAndSettle();

    final removeButton = find.byKey(
      const ValueKey('remove-local-library-local-library'),
    );
    await tester.ensureVisible(removeButton);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();

    expect(removed?.id, library.id);
    expect(find.text('Local Videos'), findsOneWidget);
  });
}

Widget _app({
  required ServerAccountState state,
  Future<void> Function(ServerAccountEntry)? onSwitch,
  Future<void> Function(ServerAccountEntry)? onLogin,
  PlaybackSettings playbackSettings = const PlaybackSettings(),
  ValueChanged<PlaybackBitrate>? onPlaybackBitrateChanged,
  ValueChanged<HardwareDecodingMode>? onHardwareDecodingModeChanged,
  ValueChanged<double>? onLongPressSpeedChanged,
  List<LocalMediaLibrary> localLibraries = const [],
  Future<void> Function(LocalMediaLibrary)? onRemoveLocalLibrary,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: ServerAccountsPage(
        state: state,
        onAddServer: () {},
        onSwitch: onSwitch ?? (_) async {},
        onLogin: onLogin ?? (_) async {},
        onLogout: (_) async {},
        onRemove: (_) async {},
        onGoHome: () {},
        playbackSettings: playbackSettings,
        onPlaybackBitrateChanged: onPlaybackBitrateChanged,
        onHardwareDecodingModeChanged: onHardwareDecodingModeChanged,
        onLongPressSpeedChanged: onLongPressSpeedChanged,
        localLibraries: localLibraries,
        onRemoveLocalLibrary: onRemoveLocalLibrary,
      ),
    ),
  );
}

ServerAccountState _state() {
  final livingRoom = _session(
    serverId: 'living-room',
    userId: 'alex',
    serverName: '客厅服务器',
    userName: 'Alex',
  );
  final study = _session(
    serverId: 'study',
    userId: 'sam',
    serverName: '书房服务器',
    userName: 'Sam',
    kind: ServerKind.emby,
  );
  final bedroomSession = _session(
    serverId: 'bedroom',
    userId: 'guest',
    serverName: '卧室服务器',
    userName: 'Guest',
  );
  return ServerAccountState(
    accounts: [
      ServerAccountEntry(
        profile: ServerProfile.fromSession(livingRoom),
        session: livingRoom,
      ),
      ServerAccountEntry(
        profile: ServerProfile.fromSession(study),
        session: study,
      ),
      ServerAccountEntry(profile: ServerProfile.fromSession(bedroomSession)),
    ],
    activeSession: livingRoom,
  );
}

AuthenticatedServer _session({
  required String serverId,
  required String userId,
  required String serverName,
  required String userName,
  ServerKind kind = ServerKind.jellyfin,
}) {
  return AuthenticatedServer(
    server: DiscoveredServer(
      kind: kind,
      name: serverName,
      version: kind == ServerKind.jellyfin ? '10.11' : '4.9',
      serverId: serverId,
      apiBaseUri: Uri.parse('http://$serverId.local:8096/'),
    ),
    userId: userId,
    userName: userName,
    deviceId: 'device-id',
    accessToken: '$serverId-token',
  );
}
