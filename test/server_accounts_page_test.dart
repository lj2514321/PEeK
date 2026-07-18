import 'package:embyplayer/src/app/theme.dart';
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
    await tester.tap(find.byKey(ValueKey('switch-${study.profile.id}')));
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
}

Widget _app({
  required ServerAccountState state,
  Future<void> Function(ServerAccountEntry)? onSwitch,
  Future<void> Function(ServerAccountEntry)? onLogin,
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
